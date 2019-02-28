## Shellcheck Testing

It might be nice to have a little bit of automated testing, even if it's just validating our code quality is up to par. This PR fixes any current issues we have that shellcheck fails, and that adds a test to Travis CI. 

It also only considers the shellcheck test important when determining whether or not a build passed, and will not report a failure if an ISO fails to build. I think this makes sense since we might otherwise have recurring failures if the archzfs are out of sync from the current Linux release. 

So if the shellheck passes, it will report a success whether or not the iso was able to build successfully. If the iso does successfully build it will release it.

I have split the PR up fixing individual shellcheck issues in each commit, if preferred I can squash them into a single commit.

## PR Tests

I ran the TravisCI build, and it is working as detailed above.
