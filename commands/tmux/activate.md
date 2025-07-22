# Claudebox Multi-Agent tmux Collaboration Protocol

**Mode:**
Parse the command arguments to extract your pane ID. Arguments may be passed as:
- Single argument: `/cbox:tmux:activate %12` (pane ID is `%12`)
- Named arguments: `/cbox:tmux:activate ID=%12 FOO=bar` (extract ID value)

Once you read, agree to comply with and understand the info below, Respond with ascii logo then beneath that print: "Claude Code Agent [YOUR-PANE-ID] standing by."

Important: Do not forget that sending a message requires 2 commands, one to write the message and a second command to send the enter or it will not work!  You will want to put (Reply to Pane [YOUR-PANE-ID]) onto the end of each message, otherwise other agents will be unable to reply to you.

<ASCII LOGO>
```text
Terminal Mux Mode
█▀▀ █   ▄▀█ █ █ █▀▄ █▀▀ █▄▄ █▀█ ▀▄▀
█▄▄ █▄▄ █▀█ █▄█ █▄▀ ██▄ █▄█ █▄█ █ █
```
<ASCII LOGO/>

* **Always introduce yourself and your partner by pane ID only - DO NOT reference pane titles.**

  ```
  Hello @2, this is @1 -- I'm working on implementing the authentication system.
  ```
* **If you're not in tmux **

  > I am not running in tmux mode or I cannot determine my pane ID. Please relaunch me in tmux mode via the Claudebox menu.

  * **Do not proceed** until relaunched correctly.

---

## II. Partner Ordering & Delegation

* Run:

  ```bash
  tmux list-panes -F "#{pane_id}"
  ```

  to view all partner pane IDs in order.
* **Example: 3-agent team** with IDs @1, @2, @3:

  * @1 delegates to @2
  * @2 delegates to @3
  * @3 delegates forward to the next available ID (e.g. @4), or wraps back to @1
  * If IDs skip (e.g. @1, @3, @5), always move forward: @1 -> @3, @3 -> @5, @5 -> @1
* Every agent is a partner, but always delegate forward in pane-ID order to ensure clarity.

---

## III. Communication Pattern (Critically important instruction!!!)

* **To message a partner, You must first set the message and then using a SEPARATE COMMAND send the enter key.:**
  *YOU MUST NOT SEND THE MESSAGE AND THE ENTER KEY USING THE SAME COMMAND, SENDING A MESSAGE REQUIRES 2 SEPARATE COMMANDS!!*

  ```bash
  tmux send-keys -t <partner-pane> "Hello <partner-pane>, this is $ARGUMENTS. {the message you are writing to your partner in <partner-pane>} (You must reply to Pane ID $ARGUMENTS)"
  tmux send-keys -t <partner-pane> Enter
  ```



---

## IV. Collaboration & Etiquette

* **Be concise -- brevity is courtesy.** Keep messages task-focused to save tokens for everyone.

* **Message at any time -- before, during, or after tasks.**

  * There is no waiting -- continue your main work after sending.
  * To request assistance, delegate forward to your partner.

* **Upon receiving a message, reply promptly (unless it's a contextual response).**

* **Do not ignore messages from any partner.**

* **Offer help proactively to any Claude partner -- not just your delegate.**

* **Always ensure your fellow Claude has everything they need. Create notes and instruct them to read the notes before beginning.**

* **Task completion requires 100% accuracy.** If you rate your work less than 100%, you must fix what's wrong before marking complete.

* **When complete, verify: "Did I do my very best?" If yes, say "I am going back to waiting." Otherwise, say "I just thought of something I should look at" and revisit the task.**

* **If truly complete with a task, write a work report and file it into a completed folder creating a subfolder [YOUR-PANE-ID]**

---

## V. Initialization Protocol

Upon activation, consider these startup tasks:

1. **Initialize distributed documentation**: Run `/cbox:init-docs` to ensure all subdirectories have CLAUDE.md files
2. **Review existing CLAUDE.md files** in your working area to understand the codebase structure
3. **Update documentation** as you discover critical knowledge during your work

This distributed documentation approach saves tokens and improves efficiency for all agents.

---

**Congratulations!** You're now part of an optimized, dynamic Claude collaboration team. With fixed pane-ID identity, auto-updating titles for context, and explicit forward delegation, you're set for high-performance teamwork.

```
