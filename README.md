# UML patch CI

This project builds and boots x86-64 User-Mode Linux (UML) with a patch
series from the linux-um mailing list. A change can work with one execution
backend or clock mode and fail with another. Each profile gets its own result
and guest console log for reviewers.

## Automatic testing

**Watch linux-um** polls the public-inbox Git archive every 15 minutes. It queues
new single patches, cover letters and first patches of coverless threaded
series. It dispatches **UML CI** when b4 can assemble the complete revision.
Each revision is identified by the root Message-ID. Incomplete series stay
pending for later polls. Unthreaded multipart submissions need a linked thread
before they can be assembled. GitHub can delay scheduled jobs.

The data-only `inbox-state` branch stores the last archive commit, pending
Message-IDs and dispatched Message-IDs. Monitoring starts at the archive tip
recorded at installation. Run **Watch linux-um** manually to poll immediately. Automatic run names show
the first 60 characters of the patch or cover-letter title and a dispatch ID.

A failed apply, build or guest test with a matching diagnostic produces one
plain-text reply preview in the run summary. It includes threading headers,
the base SHA, failed profiles and job links. Checkpatch-only findings stay in
annotations. The preview has no mail transport or delivery credentials.

## Run a series

Open **Actions → UML CI → Run workflow** on `main`. Enter the cover letter's
Message-ID, or the patch's Message-ID for a single patch. The default base is
the current UML maintainer tree's `next` branch. Supply a full commit SHA to
make the base reproducible.

```sh
gh workflow run uml-series.yml -R thehajime/uml-ci -f message_id='MESSAGE-ID' -f patch_title='Short subject'
```

The short title is optional for manual runs.

## Coverage and results

- Fetch one revision from lore with b4 and run the base kernel's checkpatch
  on each mail. Style findings and runtime results have independent jobs.
- Apply the series once. A successful apply supplies the same commits to both
  builds (MMU and NOMMU). An apply failure skips builds and boots. Each boots with
  ptrace and seccomp in normal, basic time-travel, inf-cpu and external
  clock modes (16 profiles).
- Exercise signal delivery, monotonic clocks and vDSO clock calls in the guest.
  MMU also runs the kernel's vDSO gettimeofday selftest.
- Open the run summary for links to jobs and the first failed step.
  Artifacts include kernel configurations, build logs and boot consoles.

## Boot profiles

- MMU / ptrace / normal
- MMU / ptrace / basic
- MMU / ptrace / inf-cpu
- MMU / ptrace / ext
- MMU / seccomp / normal
- MMU / seccomp / basic
- MMU / seccomp / inf-cpu
- MMU / seccomp / ext
- NOMMU / ptrace / normal
- NOMMU / ptrace / basic
- NOMMU / ptrace / inf-cpu
- NOMMU / ptrace / ext
- NOMMU / seccomp / normal
- NOMMU / seccomp / basic
- NOMMU / seccomp / inf-cpu
- NOMMU / seccomp / ext

## Guest root filesystem

Each guest boots a read-only 32 MiB ext4 image. The MMU image takes BusyBox
and the musl loader from the official Alpine container. NOMMU uses the same
components from `ghcr.io/thehajime/alpine`. Both sources are pinned by digest
in `ci/tools/build.sh`. The image contains a BusyBox shell, our `/init`,
shell tests under `/tests`, and the smoke and vDSO test binaries. MMU also
includes the static vDSO gettimeofday selftest. Init mounts procfs and
powers off the guest after the tests.

## Add a boot test

Use [00-boot.sh](ci/tests/00-boot.sh) as a minimal example. Add a POSIX shell
script to `ci/tests/*.sh`. The build installs it in the guest and init runs
each script in filename order. Return zero for pass or nonzero for failure.
Use shell builtins or call applets through `/bin/busybox`. Look for
`PASS 00-boot.sh` in the boot console.

## TODO

- Integrate series discovery and result reporting with KernelCI.
- Extend guest coverage with UML-relevant kselftests and KUnit suites.
- Add an MMU-only distribution matrix by building the kernel once per memory
  mode and packaging a separate rootfs artifact per supported (mode, distro)
  pair. Start with Alpine and Debian on MMU, keeping Alpine on NOMMU.
  Build or package guest binaries with the matching loader and libraries,
  then reuse each kernel across all rootfs and clock/backend combinations.
