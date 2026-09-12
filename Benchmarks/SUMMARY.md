# Complete measurement index

These are measured runs, including exploratory configurations and prior builds. They are not all the same solver revision or workload. Use [CURRENT_BASELINE.md](../CURRENT_BASELINE.md) for the final Release baseline and [OPTIMIZATION_LOG.md](../OPTIMIZATION_LOG.md) for comparisons, validation, and caveats. GPU phase profiles are separate `.txt` files and are not throughput results.

| Raw file | Grid | Steps | Batch | Forward | Packed inverses | Threads | Display every | R median | R range | ms/step median | Repeats |
|---|---:|---:|---:|---|---|---:|---:|---:|---:|---:|---:|
| [01-packed.csv](01-packed.csv) | 1024² | 240 | 4 | C2C | yes | 256 | 1 | 1.074553 | 1.073894–1.079969 | 1.861241 | 3 |
| [02-unpacked.csv](02-unpacked.csv) | 1024² | 240 | 4 | C2C | no | 256 | 1 | 0.718995 | 0.716871–0.721651 | 2.781665 | 3 |
| [experiment-baseline.csv](experiment-baseline.csv) | 1024² | 1200 | 4 | C2C | yes | 256 | 1 | 1.069230 | 1.059802–1.074272 | 1.870505 | 3 |
| [experiment-batch1.csv](experiment-batch1.csv) | 1024² | 1200 | 1 | C2C | yes | 256 | 1 | 0.859577 | 0.851544–0.863309 | 2.326727 | 3 |
| [experiment-batch16.csv](experiment-batch16.csv) | 1024² | 1200 | 16 | C2C | yes | 256 | 1 | 1.133828 | 1.117158–1.150820 | 1.763936 | 3 |
| [experiment-batch8.csv](experiment-batch8.csv) | 1024² | 1200 | 8 | C2C | yes | 256 | 1 | 1.088434 | 1.088117–1.089565 | 1.837504 | 3 |
| [experiment-display4.csv](experiment-display4.csv) | 1024² | 1200 | 4 | C2C | yes | 256 | 4 | 1.139916 | 1.137085–1.141155 | 1.754516 | 3 |
| [experiment-forcing-branch.csv](experiment-forcing-branch.csv) | 1024² | 1200 | 4 | C2C | yes | 256 | 1 | 1.098202 | 1.090596–1.109407 | 1.821160 | 3 |
| [experiment-threads128.csv](experiment-threads128.csv) | 1024² | 1200 | 4 | C2C | yes | 128 | 1 | 1.063036 | 1.061085–1.066929 | 1.881405 | 3 |
| [experiment-threads512.csv](experiment-threads512.csv) | 1024² | 1200 | 4 | C2C | yes | 512 | 1 | 1.070891 | 1.069610–1.072304 | 1.867605 | 3 |
| [experiment-unpacked.csv](experiment-unpacked.csv) | 1024² | 1200 | 4 | C2C | no | 256 | 1 | 0.730225 | 0.720006–0.733390 | 2.738883 | 3 |
| [final-cfl-1024.csv](final-cfl-1024.csv) | 1024² | 2400 | 4 | R2C | yes | 256 | 1 | 1.595553 | 1.593200–1.595770 | 1.769948 | 3 |
| [final-cfl-2048.csv](final-cfl-2048.csv) | 2048² | 600 | 4 | R2C | yes | 256 | 1 | 0.187099 | 0.186761–0.187393 | 8.062818 | 3 |
| [final-cfl-256.csv](final-cfl-256.csv) | 256² | 12000 | 4 | R2C | yes | 256 | 1 | 75.055163 | 74.974569–76.049055 | 0.241795 | 3 |
| [final-cfl-512.csv](final-cfl-512.csv) | 512² | 6000 | 4 | R2C | yes | 256 | 1 | 13.743266 | 13.712326–13.768108 | 0.499649 | 3 |
| [final-fixed-1024.csv](final-fixed-1024.csv) | 1024² | 2400 | 4 | R2C | yes | 256 | 1 | 1.142996 | 1.141734–1.146026 | 1.749788 | 3 |
| [final-fixed-2048.csv](final-fixed-2048.csv) | 2048² | 600 | 4 | R2C | yes | 256 | 1 | 0.248350 | 0.247063–0.248454 | 8.053155 | 3 |
| [final-fixed-256.csv](final-fixed-256.csv) | 256² | 12000 | 4 | R2C | yes | 256 | 1 | 8.316696 | 8.156237–8.335073 | 0.240480 | 3 |
| [final-fixed-512.csv](final-fixed-512.csv) | 512² | 6000 | 4 | R2C | yes | 256 | 1 | 4.014638 | 3.986078–4.026759 | 0.498177 | 3 |
| [forcing-confirm-after.csv](forcing-confirm-after.csv) | 1024² | 2400 | 4 | C2C | yes | 256 | 1 | 1.064455 | 1.059537–1.069379 | 1.878901 | 3 |
| [forcing-confirm-before.csv](forcing-confirm-before.csv) | 1024² | 2400 | 4 | C2C | yes | 256 | 1 | 1.053041 | 1.047022–1.059901 | 1.899267 | 3 |
| [r2c-after.csv](r2c-after.csv) | 1024² | 2400 | 4 | R2C | yes | 256 | 1 | 1.125366 | 1.125055–1.130847 | 1.777205 | 3 |
| [r2c-before.csv](r2c-before.csv) | 1024² | 2400 | 4 | C2C | yes | 256 | 1 | 1.036671 | 0.822350–1.076044 | 1.929259 | 3 |
| [release-cfl-1024.csv](release-cfl-1024.csv) | 1024² | 2400 | 4 | R2C | yes | 256 | 1 | 1.553099 | 1.541802–1.564579 | 1.818330 | 3 |
| [release-cfl-2048.csv](release-cfl-2048.csv) | 2048² | 600 | 4 | R2C | yes | 256 | 1 | 0.183429 | 0.183198–0.184086 | 8.224147 | 3 |
| [release-cfl-256.csv](release-cfl-256.csv) | 256² | 12000 | 4 | R2C | yes | 256 | 1 | 73.544606 | 73.272083–74.565316 | 0.246761 | 3 |
| [release-cfl-512.csv](release-cfl-512.csv) | 512² | 6000 | 4 | R2C | yes | 256 | 1 | 13.705544 | 13.649041–13.758318 | 0.501024 | 3 |
| [release-fixed-1024.csv](release-fixed-1024.csv) | 1024² | 2400 | 4 | R2C | yes | 256 | 1 | 1.118865 | 1.113294–1.125296 | 1.787526 | 3 |
| [release-fixed-2048.csv](release-fixed-2048.csv) | 2048² | 600 | 4 | R2C | yes | 256 | 1 | 0.243052 | 0.242238–0.244827 | 8.228680 | 3 |
| [release-fixed-256.csv](release-fixed-256.csv) | 256² | 12000 | 4 | R2C | yes | 256 | 1 | 6.411044 | 6.348616–6.892909 | 0.311962 | 3 |
| [release-fixed-512.csv](release-fixed-512.csv) | 512² | 6000 | 4 | R2C | yes | 256 | 1 | 3.940512 | 3.937487–3.964896 | 0.507548 | 3 |

Fixed-dt runs use dt=0.002. Files with `cfl` in their name use CFL=0.45 and a 0.02 ceiling; their actual timesteps vary. All listed offscreen trials render; the CLI also supports explicit `--no-render` comparisons, for which no performance claim is made here. The early `gpu_ms_step` column sums overlapping command-buffer intervals and must not be interpreted as GPU busy time; later `gpu_span_ms_step` corrects this instrumentation issue. R_turbo always uses measured wall time.

## Visible application and launch checks

| Raw file | Grid | Active wall s | Simulated s | R | FPS | Status |
|---|---:|---:|---:|---:|---:|---|
| [release-ui-1024.txt](release-ui-1024.txt) | 1024² | 15.062556 | 17.112001 | 1.136062 | 59.44 | Final native app; presentation FPS |
| [release-ui-2048.txt](release-ui-2048.txt) | 2048² | 15.211544 | 3.768000 | 0.247707 | 30.84 | Final native app; presentation FPS |
| [release-ui-256.txt](release-ui-256.txt) | 256² | 15.208862 | 141.632004 | 9.312466 | 58.65 | Final native app; presentation FPS |
| [release-ui-512.txt](release-ui-512.txt) | 512² | 15.011456 | 65.264000 | 4.347613 | 57.92 | Final native app; presentation FPS |
| [release-ui-eager-1024.txt](release-ui-eager-1024.txt) | 1024² | 15.003949 | 16.264000 | 1.083981 | 59.04 | Final native app; presentation FPS |
| [ui-before-1024.txt](ui-before-1024.txt) | 1024² | 15.157551 | 15.951209 | 1.052361 | 58.88 | Exploratory older UI; completion-based FPS, not final baseline |
| [ui-demand-1024.txt](ui-demand-1024.txt) | 1024² | 30.038590 | 33.716728 | 1.122447 | 59.28 | Exploratory older UI; completion-based FPS, not final baseline; overlapped build/testing |
| [ui-launch-check-256.txt](ui-launch-check-256.txt) | 256² | 3.017564 | 28.968002 | 9.599796 | 59.66 | 3-second launch smoke; not sustained |
