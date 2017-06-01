# Release checklist

  1. Update `CHANGELOG.md` with a bulletpoint list of new features and bug fixes
  2. Update version numbers in `mix.exs` and `README.md` and commit
  3. Create an annotated tag for the release: `git tag -a vx.y.z`
  4. Push last commit(s) *and* tags to GitHub
  5. Wait for the Travis builds to complete successfully
  6. Copy the latest CHANGELOG.md entry to the GitHub releases description
  7. Run `mix hex.publish`
  8. Update version numbers in `CHANGELOG.md` and `mix.exs` and append `-dev`
