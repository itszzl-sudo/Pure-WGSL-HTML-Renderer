# Pure WGSL Renderer - GPU端HTML全链路解析渲染引擎

基于WebGPU/WGSL的单页面HTML渲染工具，从分词解析到像素渲染全程在GPU端完成。

## 技术架构

```
项目根目录/
├── index.html                 # 主入口页面
├── wgsl/                      # WGSL着色器文件
│   ├── constants.wgsl         # 全局常量定义
│   ├── utils.wgsl             # 基础工具函数
│   ├── html_parser.wgsl       # HTML解析模块
│   ├── css_parser.wgsl        # CSS样式解析模块
│   ├── layout.wgsl            # 自适应布局模块
│   └── renderer.wgsl          # GPU渲染模块
├── js/                        # JavaScript驱动代码
│   ├── webgpu_init.js         # WebGPU初始化
│   └── renderer.js            # 渲染器封装
└── 技术文档.md                # 原始技术文档
```

## 功能特性

- ✅ 全程GPU端运算，无CPU中转解析
- ✅ HTML语法状态机解析，标签/文本分离
- ✅ 标准DOM树形结构构建
- ✅ 内联CSS样式解析
- ✅ 自适应流式布局
- ✅ 图文混合渲染
- ✅ 盒模型支持

## 使用说明

在浏览器中打开 `index.html` 即可运行演示。

## 致谢

本项目由 [Trae](https://www.trae.ai/) AI 编程助手辅助开发完成。Trae 在代码架构设计、模块划分、技术文档编写等方面提供了重要的帮助和指导。

## 许可证

MIT License
