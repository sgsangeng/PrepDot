import MarkdownIt from 'markdown-it'

const md = new MarkdownIt({ html: false, linkify: true, breaks: true })

export function renderMarkdown(source: string): string {
  return md.render(source)
}

export function renderInlineMarkdown(source: string): string {
  return md.renderInline(source)
}
