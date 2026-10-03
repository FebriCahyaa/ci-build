# CodeLinaro / SDM660 / 4.19

Compatibility anchor verified in the Lavender source:

LA.UM.12.2.1.r1-04000-sdm660.0

The Lavender source contains the enclosing merge:

a64d96a3e53b3739140f5f85e490cd88f3e707bd
Merge tag 'LA.UM.12.2.1.r1-04000-sdm660.0'
of https://git.codelinaro.org/clo/la/kernel/msm-4.19
into android13-4.19-sdm660

The source also contains the earlier:

4306fc221088a45b59a845653916a3a703f14fa8
Merge tag 'LA.UM.12.2.1.c26-00600-sdm660.0'

The four patches in this folder are the individual CodeLinaro/QTI
commits from the r1-04000 merge. They are useful as atomic backports and
are intentionally idempotent. The current Lavender branch should report
them as `ALREADY APPLIED`.

Do not blindly mix the 11.2.1 and 12.2.1 SDM660 release lines. The
12.2.1 line is the one directly evidenced in this source's history.

The atomic patch files are taken from commits that the source's
LA.UM.12.2.1.r1-04000 merge message identifies. They are intentionally
kept separately so the same patch can be reused against an older
sdm660 4.19 tree.
