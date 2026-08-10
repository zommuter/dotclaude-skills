# TODO — repo-beta (fixture)

The collision fixture. `id:cccc` is a class-A HOMONYM of repo-alpha's `id:cccc`
(same bare 4-hex token, different repo, no cross-repo reference to it).
`id:cafe` is the class-B case: repo-alpha carries `<!-- routed:cafe -->`, and the
token also exists here, so the cross-repo edge cannot resolve to one `(repo, id)`.

## Queue

- [ ] [ROUTINE] Homonym of repo-alpha's cccc — the composite key disambiguates it <!-- id:cccc -->
- [ ] [HARD] The routed target — also minted as cafe in a second repo <!-- id:cafe -->
