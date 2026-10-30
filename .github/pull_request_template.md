## Related issue(s): 

## Description


## Checklist
- [ ] Plugin names are kebab-name
- [ ] Properties: names are snake_case, changes to existing ones are backwards compatible (or marked `BREAKING`)
- [ ] Unit tests are added or updated
- [ ] End-to-end tests (Bruno) are added or updated
- [ ] Tested locally
- [ ] In case of a new plugin, it's added to the plugin list in config.yaml and the helm chart
- [ ] Documentation is added in docs/`<plugin-name>`

## Merge method
<!-- Pick one. Rebase is preferred. -->
- [ ] Rebase and merge 
- [ ] Merge commit
- [ ] Squash and merge (preferred) 

## Merge checklist
- [ ] Commit messages (or the PR title when squashing) follow [Conventional Commits](https://www.conventionalcommits.org/)
- [ ] Rebase or merge commit: every commit message is clean and suitable for the changelog (no `fix typo` or `wip` commits). Do an interactive rebase (`git rebase -i`) to clean up commits if needed
- [ ] Squash: the PR title is clean and suitable for the changelog
- [ ] Breaking changes are marked with `BREAKING: <description>` on the last line of the commit message
- [ ] The PR targets the right branch: `main`, or a release channel (`next` for features, `next-major` for breaking changes) if the change should not be released immediately
