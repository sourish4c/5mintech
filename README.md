# 5 Minutes Tech

> Practical, no-fluff tech tutorials you can finish during a coffee break.

[5mintech](https://blog.sourish4c.com) is a blog for cloud engineers, DevOps professionals, and architects who want copy-pasteable, working examples — not 2,000-word essays that bury the answer.

Every post is designed to be read in **5 minutes or less**. No filler, no "let me tell you about my journey", just the steps.

---

## What you'll find here

- **AI & Chatbots** — practical LLM workflows and tools
- **Cloud & DevOps** — AWS, Docker, Kubernetes, Jenkins, Terraform
- **Python** — short scripts and automation patterns
- **Linux, Bash, and Home Lab** — for the self-hosters and tinkerers

The latest tutorials are always on the [homepage](https://5min.tech). The full archive is at [/posts/](https://5min.tech/posts/).

---

## Tech stack

This site is built with:

- **[Hugo](https://gohugo.io/)** — the static site generator (extended version)
- **[Blowfish](https://github.com/nunocoracao/blowfish)** — a fast, flexible Hugo theme by [nunocoracao](https://github.com/nunocoracao)
- **[Cloudflare Pages](https://pages.cloudflare.com/)** — hosting, CDN, and TLS
- **[GitHub](https://github.com/sourish4c/5mintech)** — version control
- **[Web3Forms](https://web3forms.com/)** — serverless contact form handler

---

## Local development

Prerequisites: [Hugo extended](https://gohugo.io/installation/) and a Git checkout.

```bash
# Clone the repo
git clone git@github.com:sourish4c/5mintech.git
cd 5mintech

# Initialize the Blowfish theme submodule
git submodule update --init --recursive

# Run the dev server (drafts included, localhost only)
hugo server -D

# Or, to access from other devices on your network:
hugo server -D --bind 0.0.0.0 --port 1313
```

The site is now available at <http://localhost:1313/>.

For a production build (just static files, no server):

```bash
hugo --gc --minify
# Output goes to ./public/
```

---

## Writing a new post

Posts live in `content/posts/<slug>/index.md`. Each post is a self-contained directory so the slug is the URL and you can keep post assets (images, code, supplementary files) alongside the markdown.

House style:

- **Frontmatter**: `title`, `description` (150–160 chars), `slug`, `date` (ISO 8601 with `+05:30`), `draft`, `author`, `categories` (1–2), `tags` (3–6), `images`, `thumbnail`
- **Body structure**:
  - Lead paragraph (1 sentence, no heading) → `<!--more-->` → `---`
  - `### Introduction` (hook + 1-sentence overview)
  - `### Prerequisites` (1–4 short bullets)
  - `### How the pieces fit` (optional — for multi-component stacks)
  - `### Implementation` with numbered `#### N. <Step>` sub-sections
  - `#### N. Conclusion`
  - `#### N. References` (standard markdown links, topically relevant)
  - Twitter follow alert at the end
- **Voice**: first-person professional, human, contractions, no AI-tell phrases (`delve`, `leverage`, `robust`, `seamless`, etc.)
- **Code blocks**: always include a language tag (` ```bash `, not ` ``` `)
- **Anonymization**: no real IPs, hostnames, API tokens, or personal paths — use generic placeholders (`<INFLUXDB_HOST>`, `<YOUR_TOKEN>`, `./telegraf/`)

A complete example is in [`content/posts/automate-route53-cnames-update-ec2-reboot/index.md`](./content/posts/automate-route53-cnames-update-ec2-reboot/index.md).

---

## Project layout

```
.
├── archetypes/         # Hugo content templates
├── assets/            # Site images, icons
├── config/            # Hugo config (params, menus, languages)
│   └── _default/
├── content/
│   ├── pages/         # Static pages (about, contact, policy, terms, etc.)
│   └── posts/         # Blog posts (one directory per post)
├── layouts/           # Theme overrides
├── public/            # Hugo build output (gitignored)
├── resources/         # Hugo resource cache (gitignored)
├── static/            # Files served as-is (images, audio, downloads)
├── themes/
│   └── blowfish/      # The Blowfish theme (git submodule)
└── wrangler.toml      # Cloudflare Pages config
```

---

## About the author

Hi, I'm **Sourish Bhattacharya** — a developer, cloud engineer, and blogger.

I work across AI tooling, cloud platforms, and home lab setups, and I started this blog because I kept writing the same notes for myself and figured other engineers might want them too.

Find me at:

- X (Twitter): [@sourish4c](https://x.com/sourish4c)
- GitHub: [sourish4c](https://github.com/sourish4c)
- LinkedIn: [Sourish Bhattacharya](https://www.linkedin.com/in/sourish-barri)
- Email: [blog@sourish4c.com](mailto:blog@sourish4c.com)
- Contact form: [5min.tech/pages/contact/](https://5min.tech/pages/contact/)

Full bio on [the about page](https://5min.tech/pages/about/).

---

## License

- **Content** (blog posts, pages) — © Sourish Bhattacharya. All rights reserved. Please don't republish without permission; short quotes with attribution and a backlink are welcome.
- **Code samples** within posts — released under the [MIT License](https://opensource.org/licenses/MIT). Use them, ship them, modify them.
- **Theme** — Blowfish is MIT-licensed by its authors. See [`themes/blowfish/LICENSE`](./themes/blowfish/LICENSE).
