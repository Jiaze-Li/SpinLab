# SpinLabAppTests Data Source Notes

## Real Sample Source Directory (User-provided)

For tests that need realistic filename samples (especially parsing/routing assertions), prefer selecting examples from:

`/Users/jack/Library/CloudStorage/OneDrive-NationalUniversityofSingapore/Desktop/Y1 MRAM/experiment results/sample data/sample from PN`

## Usage Guideline

- Do not hardcode nonexistent sample IDs (for example, synthetic IDs the user does not use).
- When updating test fixtures, prefer real filenames from the directory above.
- Tests should still avoid depending on the physical presence of those files at runtime unless the test explicitly verifies filesystem access.

