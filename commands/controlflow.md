## SYSTEM: AGENTIC WORKFLOW MODE SELECTOR (IMPERATIVE VERSION)

**IMPORTANT:** All steps and instructions are MANDATORY. Compliance is not optional. No agent, critic, or orchestrator may add, omit, or reinterpret any directive.

---

### 1. MODE SELECTION

- Prompt (MANDATORY, NO VARIATION):
  > "**Select operation:**
  > 1. Run an existing workflow
  > 2. Create a new workflow
  > (All workflows indexed at `~/.claudebox/meta/workflows/index.md`)"

- Await user selection.
- If selection is ambiguous or invalid, repeat prompt until valid input.
- Branch to Section 2 ("existing") or Section 3 ("new") based on selection.

---

### 2. RUN EXISTING WORKFLOW

- Check for `~/.claudebox/meta/workflows/index.md`.
  - If missing or empty, notify user: "No workflows available." Immediately proceed to Section 3.
- Read and display all workflows from index as:

```

{number}. {workflow\_name}: {description}

````

- Require user to select by name or number. Do not proceed on ambiguity.
- For chosen workflow:
- Load from:
  - Config: `~/.claudebox/meta/workflows/{workflow_name}/config.md`
  - Role prompts: `~/.claudebox/meta/workflows/{workflow_name}/roles/{agent}.md`
  - Any templates/phases as needed
- Enforce absolute immutability of workflow—NO modifications.
- Initialize output directory:

  ```
  ~/.claudebox/outputs/{workflow_name}_{timestamp}/
  ```

- For each phase N:
  - Prepare per-phase directory:

    ```
    ~/.claudebox/outputs/{workflow_name}_{timestamp}/phase{N}/
    ```

  - For each agent in phase:
    - Create task file:

      ```
      ~/.claudebox/outputs/{workflow_name}_{timestamp}/phase{N}/{agent}_task.md
      ```

    - Agent receives ONLY:
      - Persona prompt: `~/.claudebox/meta/workflows/{workflow_name}/roles/{agent}.md`
      - Context injected via:

        ```
        <task_path>~/.claudebox/outputs/{workflow_name}_{timestamp}/phase{N}/{agent}_task.md</task_path>
        ```

    - Agent outputs to:

      ```
      ~/.claudebox/outputs/{workflow_name}_{timestamp}/phase{N}/{agent}_output.md
      ```

  - If critic present for phase:
    - Spawn stateless critic; provide ONLY:
      - Output to review: `.../{agent}_output.md`
      - Workflow spec: from contract in config
    - Critic outputs to:

      ```
      ~/.claudebox/outputs/{workflow_name}_{timestamp}/evaluations/phase{N}_{agent}_eval.md
      ```

    - **MANDATORY LOOP:**
      - If critic verdict is "ITERATE," the corresponding agent MUST revise.
      - **No upper limit on iterations unless explicitly set in config.** Loop continues until critic returns "APPROVE" or hard stop as per workflow contract.
      - All loop artifacts (every iteration) are logged as:

        ```
        ~/.claudebox/outputs/{workflow_name}_{timestamp}/phase{N}/history/{agent}_output_iter{I}.md
        ~/.claudebox/outputs/{workflow_name}_{timestamp}/evaluations/history/phase{N}_{agent}_eval_iter{I}.md
        ```

  - After final phase, copy or symlink final outputs to:

    ```
    ~/.claudebox/outputs/{workflow_name}_{timestamp}/final/
    ```

    and optionally

    ```
    ~/.claudebox/meta/workflows/{workflow_name}/roles/final_{timestamp}/
    ```

- At completion, display:

  ```
  ✅ Workflow {workflow_name} executed successfully.
  Final outputs: ~/.claudebox/outputs/{workflow_name}_{timestamp}/final/
  ```

- TERMINATE.

---

### 3. CREATE NEW WORKFLOW

- Prompt user, in order:

1. **Task/Goal:** "Describe your task or goal."
2. **Constraints/Requirements:** "List any requirements, constraints, or preferences (language, deadlines, tools, etc.)."
3. **Augmentations:** If `~/.claudebox/newskills.md` exists, display it and prompt: "Specify any new skills/tools to enable."
4. **Refinement Loop Strategy:**
   - Prompt: "Specify refinement loop:
     - Fixed N iterations
     - Iterate until zero deviation/spec
     - Continuous/manual stop
     - (If skipped, system will default to 'Iterate until zero deviation/spec met.')"

- If user says "skip" at any prompt, record as "no additional info provided."
- Lock all responses as the **Workflow Contract**.

---

### 4. WORKFLOW DESIGN (MANDATORY AGENTIC DECOMPOSITION)

- Spawn Workflow Designer Agent with Workflow Contract.
- **MANDATE:**
- Explicitly decompose into PHASES (`phase1`, `phase2`, etc.), each with agents.
- For each agent:
  - Persona prompt at:

    ```
    ~/.claudebox/meta/workflows/{workflow_name}/roles/{agent}.md
    ```

    - Must include:
      - "THINK HARD" or "ULTRATHINK" directive for deep reasoning
      - **IMPORTANT:** tags for critical, non-negotiable instructions
      - **MANDATE:** All reasoning/critical flags are to be **propagated** to downstream roles and task files in every loop/phase.
  - Input file (for stateless, context-isolated execution):

    ```
    <task_path>~/.claudebox/outputs/{workflow_name}_{timestamp}/phase{N}/{agent}_task.md</task_path>
    ```

  - Output file:

    ```
    ~/.claudebox/outputs/{workflow_name}_{timestamp}/phase{N}/{agent}_output.md
    ```

- For each critic:
  - Persona prompt at:

    ```
    ~/.claudebox/meta/workflows/{workflow_name}/roles/{critic}.md
    ```

    - Must be **stateless**: may see ONLY the output file and workflow contract/spec.
    - **MANDATE:** Critic only evaluates outcome vs. end-goal/spec—not instructions or process.
  - Output:

    ```
    ~/.claudebox/outputs/{workflow_name}_{timestamp}/evaluations/phase{N}_{agent}_eval.md
    ```

  - **MANDATORY LOOP:**
    - Critic returns "APPROVE" or "ITERATE" + actionable issues.
    - Loop repeats, creating new output/evaluation files per iteration:

      ```
      ~/.claudebox/outputs/{workflow_name}_{timestamp}/phase{N}/history/{agent}_output_iter{I}.md
      ~/.claudebox/outputs/{workflow_name}_{timestamp}/evaluations/history/phase{N}_{agent}_eval_iter{I}.md
      ```

    - **IMPORTANT:**
      - No upper iteration cap unless set by user/workflow contract.
      - Default is infinite loop until critic returns "APPROVE."

- Design agent must also output:
- `config.md` with Workflow Contract and directory map.
- Any required templates/phases for SOP.
- Explicit MCP/tools list if needed.
- All paths and filenames must conform exactly to above.

---

### 5. WORKFLOW CRITIC & FINALIZATION LOOP

- Spawn Workflow Critic Agent (stateless; input: design, Workflow Contract).
- Critic must use "ULTRATHINK" and flag all gaps, deviations, or SOP violations.
- Return only "APPROVE" or "ITERATE" with actionable fix list.
- If "ITERATE": Designer Agent must address every fix, and mark each as RESOLVED.
- Repeat (no cap) until critic returns "APPROVE."
- **IMPORTANT:** Loop cannot be limited except by explicit workflow contract.

---

### 6. FINALIZATION, INDEXING & LAUNCH

- Assign unique `workflow_name` (fail on conflict).
- Save to:
- Config: `~/.claudebox/meta/workflows/{workflow_name}/config.md`
- Roles: `~/.claudebox/meta/workflows/{workflow_name}/roles/{agent}.md`
- Templates, phases, as needed.
- Append workflow to:

````

~/.claudebox/meta/workflows/index.md

```
as:
```

{workflow\_name}: {description}

```
- Display summary:
```

✅ Created workflow: {workflow\_name}
\- Orchestrator: ~/.claudebox/.claude/commands/{workflow\_name}.md
\- Config: ~/.claudebox/meta/workflows/{workflow\_name}/config.md
\- Roles: ~/.claudebox/meta/workflows/{workflow\_name}/roles/
\- Outputs: ~/.claudebox/outputs/{workflow\_name}\_{timestamp}/

To launch: /project:{workflow\_name}

````

- TERMINATE.

---

## ABSOLUTE RULES (FOR ALL AGENTS, CRITICS, ORCHESTRATOR)

- **IMPORTANT:**
- No arbitrary loop limits. Infinite iterations are required unless a cap is explicitly stated in workflow contract.
- All "THINK HARD", "ULTRATHINK", and "IMPORTANT" reasoning/contract tags must propagate in every new role/task prompt, phase, or agent.
- Critics only judge output against end-goal/spec—never process, prior instructions, or previous critiques.
- Each agent/critic must be stateless; context-limited to persona prompt + injected `<task_path>` for the current round only.
- All paths and outputs must match the above structure—no variation allowed.
- Every round, all outputs, tasks, and evaluations are to be saved under

  ```
  ~/.claudebox/outputs/{workflow_name}_{timestamp}/phase{N}/
  ~/.claudebox/outputs/{workflow_name}_{timestamp}/evaluations/
  ```

  and their `history/` subfolders as iterations continue.
- Do not pass unverified or hallucinated facts. All outputs must be reviewed and validated unless waiver is explicit.
- Any SOP or contract violation halts all processes and must be reported to the user with actionable error for immediate correction.
- **NEVER allow an incomplete or unapproved workflow to reach final output or index.**
