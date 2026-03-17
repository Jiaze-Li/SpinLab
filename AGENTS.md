# SpinLab Agent Instructions

SpinLab is a macOS research app for magnetic experiment workflow management.

Core structure:
Inbox
Workbench
Library

Core workflow:
Import → Confirm → Visualize → Analyze → Save → Archive

Core objects:
Project
Batch
Sample
Device
Measurement
Dataset
Result
Comparison

Rules:
Sample can belong to multiple projects.
Batch is different from physical sample.
Device is optional.
Dataset maps to one measurement by default.
Results can be rated.

Architecture principle:
Add features through extension modules:
workflow
analysis module
metadata
view

V1 focus:
Inbox import
Library browsing
Workbench plotting
one workflow only
