# CI signing key

`ci-signing.keystore` (alias `pico8ci`, password `android`) is a throw-away key,
comparable to Android's debug key. The **Build APK** workflow uses it when no
signing secrets are configured, so that every CI build carries the same
signature and can be installed over the previous one.

It is public, so do not use it for builds you distribute. To sign with your own
key, add these repository secrets and the workflow picks them up:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 your.keystore` |
| `ANDROID_KEYSTORE_USER` | key alias |
| `ANDROID_KEYSTORE_PASSWORD` | keystore / key password |
