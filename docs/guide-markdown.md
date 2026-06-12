# Guide markdown reference

Everything you can use when writing guide content — static guides
(`app/views/guides/topics/*.md`) and mission guides (the admin guide editor /
paste flow). Both render through `GuideMarkdownRenderer`
([app/services/guide_markdown_renderer.rb](../app/services/guide_markdown_renderer.rb))
via `MarkdownRenderer.render_guide`.

## Standard markdown

CommonMark, plus these extensions:

| Feature | Syntax | Notes |
| --- | --- | --- |
| Strikethrough | `~~text~~` | GFM style |
| Underline | `__text__` | double underscore renders `<u>`, not bold |
| Tables | GFM pipe tables | `thead`/`tbody` etc. survive sanitization |
| Autolink | bare URLs | `https://example.com` becomes a link automatically |
| Smart punctuation | `"..."`, `--`, `...` | straight quotes → curly, dashes/ellipses converted (code spans unaffected) |
| Task lists | `- [ ]` | **not** available in guides (only in the `:standard` markdown flavor used for devlogs etc.) |

### Code blocks

Fenced code blocks with a language tag are syntax-highlighted server-side with
Rouge:

````markdown
```javascript
console.log("highlighted");
```
````

Any Rouge lexer name works (`html`, `css`, `ruby`, `bash`, ...). Unknown
languages fall back to plain text. Output is `<pre class="guide-code">` so it
picks up the guide code styling.

## Custom block shortcodes

Syntax: `:::name attr="value"` on its own line, content, then a closing `:::`
on its own line. Attribute values with spaces need double quotes. Content is
full markdown and may contain other shortcodes (nesting renders innermost-first,
up to 4 levels deep).

### `:::callout`

```markdown
:::callout type="tip" title="Pro tip"
You can use **markdown** inside, including code blocks.
:::
```

- `type` — one of `info`, `tip`, `warning`, `danger`. Missing/unknown types
  fall back to `info`.
- `title` — optional, plain text (no markdown).

Renders an `<aside class="guide-callout guide-callout--<type>">`.

### `:::collapse`

```markdown
:::collapse summary="Solution"
Hidden until expanded. Markdown works here too.
:::
```

- `summary` — the always-visible label, plain text. Defaults to "Details".

Renders a native `<details>`/`<summary>` (`guide-collapse` block). Used heavily
for spoiler-style solutions in mission guides.

⚠️ An **unknown** block shortcode name (e.g. `:::video`) is silently deleted,
content and all — typos don't error, they vanish.

## Custom inline shortcodes

Syntax: `::name[content]`. Content is plain text (escaped, no markdown) and
cannot contain `[`, `]`, or newlines. Unknown names are removed.

| Shortcode | Example | Output |
| --- | --- | --- |
| `::kbd[...]` | `Press ::kbd[Ctrl] + ::kbd[S]` | `<kbd class="guide-kbd">` keycap styling |
| `::mark[...]` | `the ::mark[important] part` | `<mark class="guide-mark">` highlight |

## Document structure: `##` headings are special

- Every `##` (H2) starts a new `<section class="guide-section">` and gets an
  anchor id (`section-<slug-of-heading>`), so `[jump](#section-my-heading)`
  works. Other heading levels do **not** get ids.
- The renderer builds an outline from the H2s — this drives the guide
  table-of-contents / section nav.
- **Mission guides:** each `##` heading *is* a step. Pasting a full guide into
  the admin editor splits it on H2s — heading text becomes the step title, the
  content below becomes the step body. Anything **before the first `##` is
  dropped**, so don't put intro content above the first H2. Inside a step body,
  headings are auto-demoted so the topmost lands at H3 (the step title owns H2).

## Raw HTML

You can write inline HTML, but it goes through the Rails sanitizer: the default
allowlist plus `u`, `kbd`, `mark`, and table tags. In practice:

- `style=` attributes, `class=`, `<script>`, `<iframe>`, `<video>` etc. are
  stripped — use the shortcodes instead.
- Links only allow `http`/`https`/`mailto`; image `src` only `http`/`https`.

## Automatic behavior (nothing to do, just good to know)

- External links open in a new tab with `rel="noopener noreferrer"`; in-page
  `#anchor` links are left alone.
- Images get `loading="lazy"`, `decoding="async"`, and send no referrer.
- Rendered output is cached by content hash (7 days), so editing a guide's
  markdown shows up immediately — no restart, no manual cache bust. Changes to
  the *renderer itself* need a `MarkdownRenderer::RENDERER_VERSION` bump.

## Limits

- Mission guide variant body: 200,000 characters max.
- Shortcode nesting: 4 levels deep; ~200 shortcode blocks per document.
