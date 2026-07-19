---
layout: home

hero:
  name: VSCodemo
  text: Ribbon 扩展调试宿主
  tagline: 以 VSCodium 为基线，仅增加 Ribbon 扩展点
  actions:
    - theme: brand
      text: 开发指南
      link: /guide/
    - theme: alt
      text: Ribbon contribution
      link: /guide/ribbon-contribution

features:
  - title: 单一功能差异
    details: 除品牌隔离外，只保留 Ribbon Part 与 contributes.ribbon 扩展点。
  - title: 面向扩展调试
    details: 不内置调试目标扩展，避免 Extension Development Host 加载重复副本。
  - title: 可持续升级
    details: VS Code 与 VSCodium 版本仍由 upstream.lock.json 锁定。
---
