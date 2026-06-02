# Workbench - Main Board Layout Notes

> Implementation-level injection points only. Layout names are not formal architecture layers.
> Slot / Region / Mount Surface are not part of the stable model.

## Definitions

### Layout

Layout is the Workbench's spatial placement model inside the Main Board. It receives declared content and assigns it to concrete areas while keeping placement separate from workflow semantics.

### Area

An Area is a coarse physical location in the shell. Areas describe where content can appear.

### Placement Name

Placement names are implementation labels used by the shell to describe what kind of content belongs in an area.

### Injection Point

An Injection Point is the concrete hook the current shell exposes to a workflow or module. It is an implementation detail in the current shell, not a formal architecture layer.

### Area vs Placement Name

- An Area is spatial.
- A Placement Name is semantic.
- An Area can host more than one placement name.
- A placement name can share an area with other placement names when the implementation allows it.

## Current Explicit Injection Points

| Injection point | Current role |
|---|---|
| `searchExtra` | Additional Search content |
| `plotControls` | Additional Plot Controls content |
| `leftExtra` | Additional left-side content in the main workspace shell |
| `rightExtra` | Additional right-side content in the main workspace shell |

## Current Placement Map

| Placement Name | Intended content |
|---|---|
| Search area | Search tools and search-adjacent workflow content |
| Selection area | Selection controls and selection-adjacent workflow content |
| Analyze lifecycle area | Analyze / run lifecycle controls and feedback |
| Plot area | Plot display content |
| Plot controls area | Plot control content |
| Save/Pack area | Save and pack controls |
| Trace/Warning/Status area | Trace, warning, and status surfaces |

## Current Runtime Note

The placement map is not fully explicit yet. Current runtime still keeps part of the placement logic hard-coded in `WorkflowWorkspaceShell`, so the existing injection points above still bridge the gap between the implementation note and the live shell.
