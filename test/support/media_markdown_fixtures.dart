/// Container examples that must stay verbatim while later deliveries survive.
const mediaMarkdownExamples = <String, String>{
  'list backtick fence': '- ```text\n  MEDIA:/out/example.pdf\n  ```',
  'list tilde fence': '- ~~~text\n  MEDIA:/out/example.pdf\n  ~~~',
  'ordered list fence': '1. ~~~text\n   MEDIA:/out/example.pdf\n   ~~~',
  'task list fence': '- [ ] ~~~text\n  MEDIA:/out/example.pdf\n  ~~~',
  'nested list fence':
      '- outer\n  - ~~~text\n    MEDIA:/out/example.pdf\n    ~~~',
  'list indented code': '- item\n\n      MEDIA:/out/example.pdf',
  'lazy blockquote': '> Example syntax:\nMEDIA:/out/example.pdf',
  'nested lazy blockquote': '> > Example syntax:\nMEDIA:/out/example.pdf',
  'list lazy blockquote': '- > Example syntax:\n  MEDIA:/out/example.pdf',
  'blockquote list fence': '> - ~~~text\n>   MEDIA:/out/example.pdf\n>   ~~~',
};
