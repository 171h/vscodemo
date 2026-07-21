export default {
  lang: 'zh-CN',
  title: 'VSCodemo',
  description: '仅增加 Ribbon 扩展点的 VSCodium 调试宿主',

  themeConfig: {
    nav: [
      { text: '首页', link: '/' },
      { text: '指南', link: '/guide/' },
      { text: '实现', link: '/implementation/' },
      { text: '发布记录', link: '/changelog/' }
    ],
    sidebar: {
      '/guide/': [
        {
          text: '使用指南',
          items: [
            { text: '开发与构建', link: '/guide/' },
            { text: '扩展贡献 Ribbon', link: '/guide/ribbon-contribution' }
          ]
        }
      ],
      '/implementation/': [
        { text: '实现记录', items: [{ text: '保留差异', link: '/implementation/' }] }
      ],
      '/changelog/': [
        {
          text: '发布记录',
          items: [
            { text: '记录索引', link: '/changelog/' },
            // 🔖 RELEASE-CHANGELOG-ITEMS — 由 scripts/release.sh 自动管理
            { text: 'v1.126.07 (2026-07-21)', link: '/changelog/v1.126.07' },
            { text: 'v1.126.06 (2026-07-20)', link: '/changelog/v1.126.06' },
            { text: 'v1.126.05 (2026-07-19)', link: '/changelog/v1.126.05' },
            { text: 'v1.126.04 (2026-07-19)', link: '/changelog/v1.126.04' },
            { text: 'v1.126.03 (2026-07-19)', link: '/changelog/v1.126.03' },
            { text: 'v1.126.02 (2026-07-18)', link: '/changelog/v1.126.02' },
            { text: 'v1.126.0 (2026-07-17)', link: '/changelog/v1.126.0' },
            { text: 'v0.0.2 (2026-07-17)', link: '/changelog/v0.0.2' },
            { text: 'v0.0.1 (2026-07-17)', link: '/changelog/v0.0.1' },
            { text: 'v0.0.8 (2026-07-17)', link: '/changelog/v0.0.8' },
            { text: 'v0.0.7-vscodemo-1 (2026-07-16)', link: '/changelog/v0.0.7-vscodemo-1' },
          ]
        }
      ]
    },
    outline: { label: '本页目录', level: [2, 3] },
    docFooter: { prev: '上一页', next: '下一页' },
    lastUpdated: { text: '最后更新' },
    search: { provider: 'local' }
  }
}
