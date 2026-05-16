# Permanent stoplist (coverage-loop)
#
# Append-only ledger across runs. Hunter must not re-raise any slug listed
# below.
- iter 1 landed: runtime-settings-copywith-omitted-map-snapshot
- iter 2 landed: resolve-capability-no-instantiation
- iter 3 landed: session-dispose-detach-failure-still-cleans-up
- iter 4 landed: service-settings-copywith-null-priority-retains-priority
- iter 5 landed: update-global-settings-reentry-guard
- iter 6 reviewer-failed: request-merge-same-priority-general-before-scoped
- iter 7 landed: session-context-copywith-clones-registry
- iter 8 landed: get-plugin-services-skip-factories-no-instantiation
- iter 9 landed: read-event-primes-scope-cache-for-later-watch
- iter 10 landed: runtime-settings-fromjson-wildcard-pin
- iter 11 landed: service-registry-copy-preserves-resolved-lazy-singleton
- iter 12 no-green: numeric-default-double-prunes-noop-override
- iter 13 landed: singleton-override-removal-clears-settings-on-reresolve
- iter 14 validator-dropped: singleton-reordered-settings-no-reinject
- iter 15 landed: get-plugin-services-with-ids-skip-factories-pairs-service-ids
