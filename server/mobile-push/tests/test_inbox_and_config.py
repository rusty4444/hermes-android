import dataclasses
import json
import subprocess
import sys
import threading
from pathlib import Path

import pytest
from conftest import PREFIX, activate, end
from test_outbox import RecordingSender

from mobile_push.config import Profile
from mobile_push.service import Runtime


def test_busy_outbox_queues_durably_and_restart_drains_without_loss(env):
    activate(env)
    end(env, turn="first")
    entered, release = threading.Event(), threading.Event()

    class BlockingSender(RecordingSender):
        def send(self, registration, payload, policy):
            entered.set()
            assert release.wait(3)
            return super().send(registration, payload, policy)

    env.runtime.sender = BlockingSender()
    thread = threading.Thread(target=env.runtime.deliver_one)
    thread.start()
    try:
        assert entered.wait(2)
        end(env, turn="while-network-in-flight")
        incoming = env.runtime.inbox.peek()
        assert json.loads(incoming["payload"])["turn_id"] == "while-network-in-flight"
    finally:
        release.set()
        thread.join(3)
    sender = RecordingSender()
    restarted = Runtime(env.profile, sender)
    restarted.initialise()
    assert restarted.deliver_one()
    assert restarted.inbox.peek() is None
    assert len(sender.hints) == 1
    assert not restarted.deliver_one()


def test_inbox_never_adopts_a_reactivated_registration_generation(env):
    activate(env)
    event = {
        "kind": "turn_done",
        "session_id": "session-a",
        "turn_id": "old-turn",
        "dedup": "old-turn",
    }
    env.runtime._queue_inbox(event, env.profile.policy())
    assert env.client.delete(PREFIX + "/registrations/phone").status_code == 200
    activate(env, installation="new-phone", registration_nonce="new_generation_0123456789abcdef")
    sender = RecordingSender()
    env.runtime.sender = sender
    assert not env.runtime.deliver_one()
    assert sender.hints == []


def test_inbox_before_opt_in_never_adopts_later_consent(env):
    event = {
        "kind": "input",
        "session_id": "session-a",
        "request_id": "before-consent",
        "dedup": "before-consent",
    }
    env.runtime._queue_inbox(event, env.profile.policy())
    activate(env)
    sender = RecordingSender()
    env.runtime.sender = sender
    assert not env.runtime.deliver_one()
    assert sender.hints == []


def test_inbox_record_then_delete_crash_replay_is_deduplicated(env):
    activate(env)
    event = {
        "kind": "turn_done",
        "session_id": "session-a",
        "turn_id": "turn-a",
        "dedup": "same-event",
    }
    policy = env.profile.policy()
    env.runtime.inbox.put(event, policy)
    env.runtime.store.record(event, policy)  # crash would occur before inbox.remove
    sender = RecordingSender()
    env.runtime.sender = sender
    assert env.runtime.deliver_one()
    assert not env.runtime.deliver_one()
    assert len(sender.hints) == 1


def test_expired_inbox_entries_are_not_renewed_and_retention_is_bounded(env):
    activate(env)
    policy = dataclasses.replace(env.profile.policy(), max_events=2)
    for index in range(4):
        env.runtime.inbox.put(
            {
                "kind": "input",
                "session_id": "session-a",
                "request_id": str(index),
                "dedup": str(index),
            },
            policy,
        )
    with env.runtime.inbox.connection() as db:
        assert db.execute("SELECT count(*) FROM inbox").fetchone()[0] == 2
        db.execute("UPDATE inbox SET expires_at=0")
    env.runtime.sender = RecordingSender()
    assert not env.runtime.deliver_one()
    assert env.runtime.inbox.peek() is None
    assert env.runtime.sender.hints == []


def test_inbox_resolution_drains_before_unsent_attention_hint(env):
    activate(env)
    env.runtime.human_input(kind="approval", session_id="session-a", request_id="observer-id")
    env.runtime.inbox.put(
        {
            "kind": "input_resolved",
            "session_id": "session-a",
            "request_id": "observer-id",
            "dedup": "input_resolved:session-a:observer-id",
        },
        env.profile.policy(),
    )
    sender = RecordingSender()
    env.runtime.sender = sender
    assert env.runtime.deliver_one()
    assert [hint["kind"] for hint in sender.hints] == ["input_resolved"]


def test_missing_policy_denies_and_durable_lookup_never_creates_core_db(tmp_path):
    profile = Profile(tmp_path / "missing")
    assert not profile.policy().enabled
    assert not profile.durable("session-a")
    assert not (profile.home / "state.db").exists()


@pytest.mark.parametrize("mode", [0o644, 0o666])
def test_operator_policy_and_key_require_private_file_permissions(env, mode):
    path = env.profile.directory / "config.json"
    path.chmod(mode)
    with pytest.raises(ValueError):
        env.profile.policy()
    path.chmod(0o600)
    key = env.profile.policy().vapid_key
    key.chmod(mode)
    with pytest.raises(ValueError):
        env.profile.policy().public_key()


def test_private_files_reject_symlinks(env):
    path = env.profile.directory / "config.json"
    target = path.with_suffix(".backup")
    path.rename(target)
    path.symlink_to(target)
    with pytest.raises(OSError):
        env.profile.policy()


def test_vapid_generator_cli_creates_private_key_and_refuses_overwrite(tmp_path):
    script = Path(__file__).resolve().parents[1] / "generate_vapid.py"
    output = tmp_path / "generated.pem"
    result = subprocess.run(
        [sys.executable, str(script), "--output", str(output)],
        check=True,
        capture_output=True,
        text=True,
    )
    assert output.stat().st_mode & 0o777 == 0o600
    assert "PRIVATE KEY" not in result.stdout
    failed = subprocess.run(
        [sys.executable, str(script), "--output", str(output)], capture_output=True, text=True
    )
    assert failed.returncode != 0
    assert "PRIVATE KEY" not in failed.stderr


def test_exceptions_never_log_endpoint_or_keys(env, caplog):
    activate(env)
    end(env)

    class Broken:
        def send(self, *args):
            raise RuntimeError("PRIVATE endpoint auth subscription secret")

    env.runtime.sender = Broken()
    assert env.runtime.deliver_one()
    assert "PRIVATE" not in caplog.text and "subscription secret" not in caplog.text
