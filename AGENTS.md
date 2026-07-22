## Release and local install rules

- Develop every new feature and fix on the `beta` branch first.
- Publish test builds only as GitHub prereleases: tags use `vX.Y.Z-beta.N`.
- Promote a beta to a stable release only when Sergey explicitly asks for a release.
- A stable release is created on `main` as one clean commit named `Release X.Y.Z`, then tagged `vX.Y.Z`.
- Do not build, install, replace, launch, or otherwise modify the copy in `/Applications` unless Sergey explicitly asks to install it locally. Publishing a beta or stable release does not imply local installation.
- Before a release, keep the version aligned in the Xcode project, both `Info.plist` files, `scripts/make-release.command`, and `CHANGELOG.md`.

