# Attribution and status

This repository is a community derivative of
[rusty4444/hermes-android](https://github.com/rusty4444/hermes-android).

The Remote Gateway additions are maintained independently and are not an
official Hermes Agent, Nous Research, or upstream Hermes Android release.

The upstream snapshot used for the Remote Gateway work lacked a canonical
licence file, but its README already declared the application MIT-licensed.
The root [LICENSE](LICENSE) records those existing application terms in full;
it does not relicense third-party code or assets. Copyright and other rights
remain with their respective authors. Source history and contributor
attribution are preserved.

The bundled Cinzel font retains its [SIL Open Font License 1.1](assets/fonts/OFL.txt).
The embedded FCM distributor retains its upstream LGPL-2.1-or-later terms; see
the [Library notice](third_party/embedded-push-notice.md),
[verbatim licence](third_party/licenses/embedded-fcm-distributor-LGPL-2.1.txt)
and [source/relink instructions](third_party/embedded-push-relink.md).
Other dependencies retain their own licences and notices.

Synthetic fixture credentials are test data only. No private gateway
credentials, release signing keys, device profiles, or operator logs are part
of the public source tree.
