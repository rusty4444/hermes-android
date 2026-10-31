import 'dart:math';

import 'connection_manager.dart';

/// Provisions a fresh, collision-free folder on the gateway host for a
/// name-only Project created from the phone.
///
/// A Project owns its chats by folder (cwd-prefix), so a Project with no
/// folder cannot hold a session on gateways that lack direct assignment.
/// The Desktop app forces the user to pick a folder at create time; the
/// phone flow instead asks the dashboard to make one under the server's
/// projects root (`<locked_root>` when the dashboard is locked, else
/// `<home>/Projects`), so a name-only Project still gets a real home.
///
/// **Never adopts an existing folder.** Every candidate is probed first
/// and only an authoritative 404 counts as free — a 403 (unreadable),
/// 400 (exists but is not a directory) or a transport failure is NOT
/// evidence of absence, and treating it as such was the previous failure
/// mode where a new project silently bound to a pre-existing directory.
///
/// **Ownership is proven by an unguessable name plus a marker.** The
/// stock `POST /api/files/mkdir` is `exist_ok=True` (`files.py`:
/// `target.mkdir(parents=True, exist_ok=True)`): a 200 says nothing about
/// who created the directory. A human-readable candidate name cannot
/// close the probe→mkdir window at all — a concurrent actor who knows the
/// name (any other client provisioning the same slug) can create the same
/// EMPTY directory after our 404 probe, and our marker would then be the
/// only entry in a folder we did not create. The candidate name therefore
/// carries 64 bits of randomness: accidental or non-cooperating collision is
/// extremely unlikely, although the non-atomic mkdir cannot prove which actor
/// created the directory. The marker (an unguessable
/// `hermes-provision-<token>.owner`
/// written inside, read back with the directory listing showing it as the
/// only entry) stays as defense-in-depth: it proves write access and
/// rejects any folder that already carries someone else's contents. A
/// candidate whose marker cannot be written or verified is abandoned
/// (never adopted, never deleted — it may not be ours).
abstract class ProjectFolderProvisioner {
  /// Returns the absolute path of a newly created folder for [slug], or
  /// `null` when nothing could be provisioned (no projects root reachable,
  /// every candidate taken, or the host refused the write). Callers treat
  /// `null` as "stay folderless", never as a create failure.
  Future<String?> provision(String slug);
}

/// Outcome of probing one candidate path against the dashboard files
/// router. Only [missing] authorizes creation.
enum _Probe {
  /// 404 — authoritative: nothing lives at this path.
  missing,

  /// 200 — a directory already lives here.
  present,

  /// 403 — unreadable/forbidden. Existence is unknowable; never treat as
  /// free, and a denied write will not change with a suffix, so the caller
  /// stops the whole loop.
  forbidden,

  /// 400 — the path exists but is not a directory (or is otherwise
  /// rejected by the router). Occupied.
  occupied,

  /// Any other status or a transport failure: existence is unknowable.
  /// The candidate is skipped, never created on top of.
  unknown,
}

class DashboardFolderProvisioner implements ProjectFolderProvisioner {
  final DashboardClient dashboard;

  /// Number of `-N` suffix attempts before giving up on provisioning.
  static const _maxCandidates = 50;

  /// Consecutive [ _Probe.unknown ] results before aborting: a server
  /// that cannot answer existence probes cannot safely provision at all,
  /// and suffix-cycling 50 doomed probes buys nothing.
  static const _maxConsecutiveUnknown = 3;

  const DashboardFolderProvisioner(this.dashboard);

  /// Returns the absolute path of a newly created folder for [slug], or
  /// `null` when nothing could be provisioned (no projects root reachable,
  /// every candidate taken, or the host refused the write). Callers treat
  /// `null` as "stay folderless", never as a create failure.
  @override
  Future<String?> provision(String slug) async {
    final base = _sanitize(slug);
    if (base.isEmpty) return null;
    final root = await _projectsRoot();
    if (root == null) return null;
    // One unguessable token per provision() call, folded into EVERY
    // candidate name. The probe→mkdir window cannot be closed by any
    // check (stock mkdir is exist_ok=True), so the name itself must be
    // impractical for an independent concurrent actor to pre-create: the token
    // is 64 random bits. The -N suffix still
    // rotates on probe-present so a retried provision of the same slug
    // never reuses a name.
    final nonce = _ownerToken().substring(0, 16);
    var consecutiveUnknown = 0;
    for (var suffix = 0; suffix < _maxCandidates; suffix++) {
      final candidate = suffix == 0
          ? '$root/$base-$nonce'
          : '$root/$base-$nonce-$suffix';
      final probe = await _probe(candidate);
      switch (probe) {
        case _Probe.forbidden:
          // A denied read means the whole region is off-limits to us —
          // suffixing cannot help. Stop rather than burn 50 doomed probes.
          return null;
        case _Probe.present:
        case _Probe.occupied:
          consecutiveUnknown = 0;
          continue;
        case _Probe.unknown:
          // Existence unknowable: skip this name, but don't suffix-spam a
          // server that is failing every probe.
          consecutiveUnknown++;
          if (consecutiveUnknown >= _maxConsecutiveUnknown) return null;
          continue;
        case _Probe.missing:
          // Authoritatively free — attempt the create below.
          break;
      }
      try {
        await dashboard.apiPost('files/mkdir', body: {'path': candidate});
      } catch (error) {
        // A denied write (403: outside the locked root, or a name the
        // server guards like `pairing`) will not change with a suffix —
        // stop rather than burn 50 doomed requests.
        if (error.toString().contains('403')) return null;
        // 409 (a file sits at that path) or a race with a concurrent
        // create: try the next suffix rather than give up.
        consecutiveUnknown = 0;
        continue;
      }
      // The stock mkdir is exist_ok=True: a 200 here does NOT prove we
      // created the directory. Claim it instead: write an unguessable
      // marker inside and read it back. Only a folder writable enough to hold
      // our secret token and uncontested at verification can pass this check;
      // a folder we cannot write into is not ours to adopt.
      if (await _claimOwnership(candidate)) {
        return candidate;
      }
      consecutiveUnknown = 0;
      continue;
    }
    return null;
  }

  /// Writes an unguessable ownership marker into [path] and verifies the
  /// directory is exclusively ours: the listing must contain exactly one
  /// entry and it must be our marker file. Emptiness proves nothing about
  /// who created the folder, and a marker that merely exists proves only
  /// that we can write here — two racing callers could each drop their own
  /// marker and both "verify". Requiring our marker to be the ONLY entry
  /// rejects a claim once a racer's marker is visible. Combined with the
  /// unguessable candidate path, this is practical collision resistance, not
  /// an atomic ownership primitive.
  /// A failed write, a mismatched read, or a multi-entry listing means
  /// the candidate is abandoned — never adopted, never deleted (it may
  /// belong to the concurrent creator that won the mkdir race).
  Future<bool> _claimOwnership(String path) async {
    final token = _ownerToken();
    final markerName = 'hermes-provision-$token.owner';
    final markerPath = '$path/$markerName';
    try {
      await dashboard.apiPost(
        'fs/write-text',
        body: {'path': markerPath, 'content': token},
      );
    } catch (_) {
      // Write refused (read-only mount, permission, path policy): the
      // folder is not ours to claim.
      return false;
    }
    try {
      final res = await dashboard.apiGet(
        'files',
        queryParameters: {'path': path},
      );
      final entries = res['entries'];
      if (entries is! List || entries.length != 1) return false;
      final entry = entries.first;
      if (entry is! Map) return false;
      if (entry['name'] != markerName) return false;
      // Confirm the marker content round-trips: the listing proves the
      // name, the read proves the unguessable token is really on disk.
      final marker = await dashboard.apiGet(
        'fs/read-text',
        queryParameters: {'path': markerPath},
      );
      return marker['text'] == token && marker['binary'] != true;
    } catch (_) {
      // Listing/read unverifiable after a "successful" write: abandon the
      // candidate rather than adopt on a partial proof.
      return false;
    }
  }

  /// 128 bits of randomness in hex — the marker name and content are
  /// both unguessable, so no other writer can forge a claim by guessing
  /// the token, and the random name avoids colliding with a real file.
  static String _ownerToken() {
    final rand = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(rand.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  /// The directory new project folders live under.
  ///
  /// A locked dashboard (hosted/container) can only write inside its root,
  /// so the root itself is the projects dir. An unlocked one browses from
  /// the server's home, where `<home>/Projects` is the conventional root.
  Future<String?> _projectsRoot() async {
    try {
      final res = await dashboard.apiGet('files');
      final locked = res['locked_root'];
      if (locked is String && locked.trim().isNotEmpty) {
        return _trimTrailingSlash(locked.trim());
      }
      final home = res['path'];
      if (home is String && home.trim().isNotEmpty) {
        return '${_trimTrailingSlash(home.trim())}/Projects';
      }
    } catch (_) {
      // No readable dashboard means no provisioning; the caller degrades.
    }
    return null;
  }

  /// Classifies one existence probe of [path] against GET /api/files.
  ///
  /// The stock router answers 404 for a missing path, 400 when the path
  /// exists but is not a directory, 403 when it is unreadable/forbidden.
  /// Only the 404 is authoritative absence; everything else keeps the
  /// candidate off the create path.
  Future<_Probe> _probe(String path) async {
    try {
      await dashboard.apiGet('files', queryParameters: {'path': path});
      return _Probe.present;
    } on DashboardHttpException catch (e) {
      return switch (e.statusCode) {
        404 => _Probe.missing,
        403 => _Probe.forbidden,
        400 => _Probe.occupied,
        _ => _Probe.unknown,
      };
    } catch (_) {
      return _Probe.unknown;
    }
  }

  /// Keeps the slug filesystem-safe on every host while staying recognizable.
  static String _sanitize(String slug) {
    final cleaned = slug
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^[.\-]+'), '')
        .replaceAll(RegExp(r'[.\-]+$'), '');
    return cleaned;
  }

  static String _trimTrailingSlash(String path) {
    var end = path.length;
    while (end > 1 && (path[end - 1] == '/' || path[end - 1] == r'\')) {
      end--;
    }
    return path.substring(0, end);
  }
}
