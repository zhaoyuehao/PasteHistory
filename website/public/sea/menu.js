// A single menu controller for the menu bar, secondary click and touch.
export function finderMenu(root, desk, panel) {
  let source, sub, owner, timer;
  const enabled = (box) => [...box.querySelectorAll("button:not(:disabled)")];
  function position(box, x, y) {
    box.style.left =
      Math.max(4, Math.min(x, desk.clientWidth - box.offsetWidth - 4)) + "px";
    box.style.top =
      Math.max(4, Math.min(y, desk.clientHeight - box.offsetHeight - 4)) + "px";
  }
  function collapse() {
    clearTimeout(timer);
    sub?.remove();
    sub = null;
    owner?.setAttribute("aria-expanded", "false");
    owner = null;
  }
  function close(restore = false) {
    if (panel.hidden) return;
    collapse();
    panel.hidden = true;
    if (restore && source?.isConnected) source.focus({ preventScroll: true });
  }
  function fill(box, items) {
    box.replaceChildren();
    box.setAttribute("role", "menu");
    box.tabIndex = -1;
    for (const entry of items) {
      if (entry === null) {
        const hr = document.createElement("hr");
        hr.setAttribute("role", "separator");
        box.append(hr);
        continue;
      }
      const [label, action, shortcut] = entry;
      if (entry.length === 1) {
        const caption = document.createElement("small");
        caption.textContent = label;
        box.append(caption);
        continue;
      }
      const btn = document.createElement("button");
      btn.type = "button";
      btn.tabIndex = -1;
      btn.textContent = label;
      btn.setAttribute("role", "menuitem");
      btn.disabled = action == null;
      if (shortcut || Array.isArray(action)) {
        const right = document.createElement("span");
        right.setAttribute("aria-hidden", "true");
        right.textContent = Array.isArray(action) ? "›" : shortcut;
        btn.append(right);
      }
      function expand(focus) {
        if (owner !== btn) {
          collapse();
          owner = btn;
          sub = document.createElement("div");
          sub.className = "panel submenu";
          desk.append(sub);
          fill(sub, action);
          const r = btn.getBoundingClientRect(),
            p = panel.getBoundingClientRect();
          position(
            sub,
            p.right + sub.offsetWidth < desk.clientWidth
              ? p.right - 2
              : p.left - sub.offsetWidth + 2,
            r.top - 5,
          );
          btn.setAttribute("aria-expanded", "true");
        }
        if (focus) enabled(sub)[0]?.focus();
      }
      if (Array.isArray(action)) {
        btn.setAttribute("aria-haspopup", "menu");
        btn.setAttribute("aria-expanded", "false");
        btn.onclick = () => expand(true);
      } else if (action)
        btn.onclick = () => {
          close(true);
          action();
        };
      btn.onpointerenter = () => {
        clearTimeout(timer);
        btn.focus({ preventScroll: true });
        if (box === panel)
          timer = setTimeout(
            () => (Array.isArray(action) ? expand(false) : collapse()),
            120,
          );
      };
      box.append(btn);
    }
  }
  function open(x, y, items, from, label) {
    collapse();
    source = from;
    fill(panel, items);
    panel.setAttribute("aria-label", label || "菜单");
    panel.hidden = false;
    position(panel, x, y);
    panel.focus({ preventScroll: true });
  }
  root.addEventListener("keydown", (e) => {
    if (panel.hidden) return;
    const box = sub?.contains(e.target) ? sub : panel,
      rows = enabled(box),
      index = rows.indexOf(root.activeElement);
    switch (e.key) {
      case "ArrowDown":
        rows[(index + 1) % rows.length]?.focus();
        break;
      case "ArrowUp":
        rows[(index <= 0 ? rows.length : index) - 1]?.focus();
        break;
      case "Home":
        rows[0]?.focus();
        break;
      case "End":
        rows.at(-1)?.focus();
        break;
      case "ArrowRight":
        if (root.activeElement?.hasAttribute("aria-haspopup"))
          root.activeElement.click();
        break;
      case "ArrowLeft":
        if (sub) {
          const b = owner;
          collapse();
          b.focus();
        }
        break;
      case "Escape":
      case "Tab":
        close(true);
        break;
      default:
        return;
    }
    e.preventDefault();
    e.stopImmediatePropagation();
  });
  document.addEventListener(
    "pointerdown",
    (e) => {
      if (!panel.hidden && !e.composedPath().includes(root.host)) close();
    },
    true,
  );
  root.addEventListener("pointerdown", (e) => {
    if (!e.target.closest(".panel")) close();
  });
  window.addEventListener("blur", () => close());
  window.addEventListener("resize", () => close());
  return { open, close };
}
