# Pure WGSL HTML Renderer 技术原理与架构文档

## 一、项目概述

### 1.1 项目目标

本项目实现了一个完全运行在GPU端的HTML解析和渲染引擎，从HTML词法分析、DOM树构建、CSS样式解析、布局计算到最终像素渲染，全部在WebGPU/WGSL着色器中完成，无需CPU参与核心渲染逻辑。

### 1.2 核心技术栈

- **WebGPU API** - 浏览器原生GPU计算接口
- **WGSL (WebGPU Shading Language)** - WebGPU专用着色器语言
- **Canvas 2D** - 像素数据回传和最终显示

### 1.3 技术优势

✅ **全链路GPU计算** - 解析、布局、渲染全程在GPU端执行
✅ **并行计算** - 利用GPU大规模并行能力，像素级渲染
✅ **零CPU开销** - 渲染逻辑完全卸载到GPU
✅ **原生标准兼容** - 支持标准HTML和内联CSS
✅ **高性能** - 适合批量渲染和实时更新场景

---

## 二、整体架构

### 2.1 系统架构图

```
┌─────────────────────────────────────────────────────────┐
│                      CPU 端                             │
├─────────────────────────────────────────────────────────┤
│  HTML输入 → UTF-8编码 → GPU缓冲区上传                   │
│                                         ↓               │
│  像素数据回传 ← Canvas 2D绘制 ← 像素缓冲区读取           │
└─────────────────────────────────────────────────────────┘
                          ↓ GPU内部
┌─────────────────────────────────────────────────────────┐
│                    GPU 端计算管线                        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────┐    ┌──────────────┐    ┌───────────┐ │
│  │  HTML解析管线  │ →  │  CSS解析管线  │ →  │ 布局计算  │ │
│  │  (Parse Pass) │    │ (CSS Parser) │    │ (Layout) │ │
│  └──────────────┘    └──────────────┘    └───────────┘ │
│         ↓                    ↓                  ↓       │
│         └────────────────────┴──────────────────┘       │
│                          ↓                              │
│                   ┌──────────────┐                     │
│                   │ 渲染管线      │                     │
│                   │(Render Pass)  │                     │
│                   │ 800×600像素   │                     │
│                   └──────────────┘                     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 2.2 数据流架构

```
HTML字符串
    ↓
UTF-8字节流 (Uint32Array)
    ↓
┌─────────────────────────────┐
│    Storage Buffer          │
│  @binding(0) html_source    │
└─────────────────────────────┘
    ↓
┌─────────────────────────────┐
│  Parse Pass (Compute)       │
│  - HTML词法分析             │
│  - DOM树构建                │
│  - 属性提取                 │
└─────────────────────────────┘
    ↓
┌─────────────────────────────┐
│    Storage Buffer          │
│  @binding(1) dom_result    │
│  DomRootTree + DomNode[]    │
└─────────────────────────────┘
    ↓
┌─────────────────────────────┐
│  CSS解析 (Compute)          │
│  - 解析style属性            │
│  - 提取样式值               │
└─────────────────────────────┘
    ↓
┌─────────────────────────────┐
│  Layout计算 (Compute)       │
│  - 递归计算布局坐标         │
│  - 流式布局排布             │
└─────────────────────────────┘
    ↓
┌─────────────────────────────┐
│  Render Pass (Compute)      │
│  16×16工作组的并行像素渲染   │
│  50×37.5 = 1875个计算单元   │
└─────────────────────────────┘
    ↓
┌─────────────────────────────┐
│    Storage Buffer           │
│  @binding(2) pixel_buf     │
│  vec4<f32>[800×600]        │
└─────────────────────────────┘
    ↓
CopyBufferToBuffer (GPU→GPU)
    ↓
┌─────────────────────────────┐
│    Readback Buffer          │
│  MAP_READ + COPY_DST        │
└─────────────────────────────┘
    ↓ CPU读取
JavaScript Float32Array
    ↓
Canvas 2D ImageData
    ↓
浏览器显示
```

---

## 三、核心模块详解

### 3.1 HTML解析模块

#### 3.1.1 词法分析器设计

采用状态机模式实现HTML词法分析，主要状态包括：

```
STATE_IDLE ─┬─ '<' ─→ STATE_IN_TAG
            │              │
            │   ┌─ '!' ─→ STATE_IN_COMMENT
            │   │
            │   └─ '/' ─→ STATE_CLOSE_TAG
            │              │
            │   └─ 其他字符 ─→ STATE_TAG_NAME
            │
            └─ 其他字符 ─→ STATE_IN_TEXT
```

#### 3.1.2 关键解析逻辑

**标签识别**
```wgsl
// 检测到 '<' 字符，进入标签模式
if (c == 60u) {  // '<'
    in_tag = true;
    tag_start = html_ptr + 1;
}

// 检测到 '>' 字符，结束标签解析
if (c == 62u && in_tag) {  // '>'
    // 处理标签内容
    in_tag = false;
}
```

**注释过滤**
```wgsl
// 识别 <!-- 注释开始
if (html_ptr + 3u < html_len &&
    html_source[html_ptr + 1u] == 33u &&      // '!'
    html_source[html_ptr + 2u] == 45u &&      // '-'
    html_source[html_ptr + 3u] == 45u) {       // '-'
    in_comment = true;
}

// 识别 --> 注释结束
if (in_comment &&
    html_ptr + 2u < html_len &&
    html_source[html_ptr] == 45u &&
    html_source[html_ptr + 1u] == 45u &&
    html_source[html_ptr + 2u] == 62u) {
    in_comment = false;
}
```

**文本节点识别**
```wgsl
// 收集标签间的文本内容
if (!in_tag && !in_comment && !is_blank_char(c)) {
    if (text_start == INVALID) {
        text_start = html_ptr;  // 文本开始位置
    }
}

// 遇到 '<' 时，结束文本收集
if (c == 60u && text_start != INVALID) {
    // 创建文本节点
    let text_len = html_ptr - text_start;
    if (text_len > 0) {
        create_text_node(text_start, text_len);
    }
}
```

#### 3.1.3 节点创建与DOM树构建

**栈结构管理嵌套关系**
```wgsl
var node_stack: array<u32, 64>;  // 嵌套栈
var stack_ptr: u32 = 1u;
node_stack[0] = root_node_id;     // 根节点入栈

// 开始标签入栈
if (!is_close) {
    let new_idx = create_dom_node(node_type, parent_idx);
    node_stack[stack_ptr] = new_idx;
    stack_ptr += 1u;
}

// 结束标签出栈
if (is_close) {
    stack_ptr -= 1u;
}
```

**父子关系绑定**
```wgsl
fn create_dom_node(dom_tree, node_type, parent_idx) -> u32 {
    let idx = dom_tree.total_node;

    var node = DomNode();
    node.parent_idx = parent_idx;

    // 绑定为父节点的第一个子节点
    if (parent.first_child == INVALID) {
        parent.first_child = idx;
    } else {
        // 追加到兄弟链表末尾
        var sibling = parent.first_child;
        while (nodes[sibling].next_sibling != INVALID) {
            sibling = nodes[sibling].next_sibling;
        }
        nodes[sibling].next_sibling = idx;
    }

    dom_tree.total_node += 1u;
    return idx;
}
```

### 3.2 CSS样式解析模块

#### 3.2.1 解析流程

```
style="width:200px;height:100px;background:#ff0000"
         ↓           ↓              ↓
      属性1       属性2          属性3
         ↓           ↓              ↓
    ┌─────────────────────────────────────────┐
    │  按 ';' 分割                           │
    └─────────────────────────────────────────┘
         ↓           ↓              ↓
    width:200px  height:100px  background:#ff0000
         ↓           ↓              ↓
    ┌─────────────────────────────────────────┐
    │  按 ':' 分割 key:value                 │
    └─────────────────────────────────────────┘
         ↓           ↓              ↓
       key        key           key
      "width"   "height"    "background"
         ↓           ↓              ↓
       value      value          value
     "200px"    "100px"       "#ff0000"
         ↓           ↓              ↓
    ┌─────────────────────────────────────────┐
    │  字节匹配识别属性名                      │
    └─────────────────────────────────────────┘
         ↓           ↓              ↓
    width=200   height=100   background=#ff0000
```

#### 3.2.2 属性名匹配

```wgsl
fn apply_style_property(source, key_s, key_e, val_s, val_e, style) {
    let key_len = key_e - key_s;

    // width 属性 (5个字符)
    if (key_len == 5u) {
        if (source[key_s]     == 119u &&  // 'w'
            source[key_s + 1u] == 105u &&  // 'i'
            source[key_s + 2u] == 100u &&  // 'd'
            source[key_s + 3u] == 116u &&  // 't'
            source[key_s + 4u] == 104u) {  // 'h'
            (*style).width = parse_css_px(source, val_s, val_e);
        }
    }

    // background-color 属性 (16个字符)
    if (key_len == 16u) {
        if (source[key_s]      == 98u &&   // 'b'
            source[key_s + 1u]  == 97u &&  // 'a'
            source[key_s + 2u]  == 99u &&  // 'c'
            // ... 完整匹配
            source[key_s + 15u] == 114u) { // 'r'
            (*style).bg_color = css_color_to_rgba(source, val_s, val_e);
        }
    }
}
```

#### 3.2.3 数值解析

**像素值解析**
```wgsl
fn parse_css_px(source, start, end) -> f32 {
    var result: f32 = 0.0;
    for (var i: u32 = start; i < end; i++) {
        let c = source[i];
        // '0'-'9' 的ASCII码是48-57
        if (c >= 48u && c <= 57u) {
            result = result * 10.0 + f32(c - 48u);
        } else if (c == 112u || c == 120u) {  // 'p' 或 'x'
            break;  // 遇到px单位，停止解析
        }
    }
    return result;
}
```

**十六进制颜色解析**
```wgsl
fn css_color_to_rgba(source, start, end) -> vec4<f32> {
    var color = vec4<f32>(0.0, 0.0, 0.0, 1.0);

    // 格式: #RRGGBB (7个字符)
    if (end - start >= 7u && source[start] == 35u) {  // '#'
        color.r = f32(hex_to_int(source[start + 1]) * 16 +
                      hex_to_int(source[start + 2])) / 255.0;
        color.g = f32(hex_to_int(source[start + 3]) * 16 +
                      hex_to_int(source[start + 4])) / 255.0;
        color.b = f32(hex_to_int(source[start + 5]) * 16 +
                      hex_to_int(source[start + 6])) / 255.0;
    }
    return color;
}
```

### 3.3 布局计算模块

#### 3.3.1 布局算法

采用递归深度优先遍历计算每个节点的布局位置：

```wgsl
fn calculate_layout(dom_tree) {
    // 初始化根节点
    var root = dom_tree.nodes[dom_tree.root_node_id];
    root.style.layout_x = 10.0;
    root.style.layout_y = 10.0;
    root.style.content_w = CANVAS_W - 20.0;
    root.style.content_h = CANVAS_H - 20.0;

    // 访问标记数组，防止重复访问
    var visited: array<bool, 512>;
    for (var i = 0u; i < 512u; i++) {
        visited[i] = false;
    }

    // 递归计算子节点布局
    layout_node_children(dom_tree, root_node_id, &visited);
}

fn layout_node_children(dom_tree, parent_idx, visited) {
    if (visited[parent_idx]) { return; }
    visited[parent_idx] = true;

    var parent = dom_tree.nodes[parent_idx];

    // 当前子节点的起始位置
    var current_x = parent.layout_x + parent.padding_left;
    var current_y = parent.layout_y + parent.padding_top;

    var child_idx = parent.first_child;
    while (child_idx != INVALID && child_idx < dom_tree.total_node) {
        var child = dom_tree.nodes[child_idx];

        // 跳过空白文本节点
        if (child.is_text_node &&
            (child.content_w <= 0.0 || child.content_h <= 0.0)) {
            child.skip_render = true;
        }

        if (!child.skip_render) {
            // 计算子节点尺寸
            var child_w = select(child.content_w, child.width,
                                  child.width > 0.0);
            var child_h = select(child.content_h, child.height,
                                  child.height > 0.0);

            // 设置布局坐标
            child.layout_x = current_x + child.margin_left;
            child.layout_y = current_y + child.margin_top;

            // 更新流式布局指针
            if (child.is_block) {
                current_y += child_h + child.margin_top + 8.0;
            } else {
                current_x += child_w + child.margin_left + 4.0;
            }
        }

        // 递归处理嵌套子节点
        if (child.first_child != INVALID) {
            layout_node_children(dom_tree, child_idx, visited);
        }

        child_idx = child.next_sibling;
    }
}
```

#### 3.3.2 盒模型计算

```
┌─────────────────────────────────────────┐
│              margin                      │
│  ┌───────────────────────────────────┐  │
│  │           border                   │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │         padding             │  │  │
│  │  │  ┌───────────────────────┐  │  │  │
│  │  │  │                       │  │  │  │
│  │  │  │     content area     │  │  │  │
│  │  │  │                       │  │  │  │
│  │  │  └───────────────────────┘  │  │  │
│  │  │                               │  │  │
│  │  └─────────────────────────────┘  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### 3.4 渲染模块

#### 3.4.1 并行渲染架构

```
┌────────────────────────────────────────────────────────────┐
│                    Canvas 800 × 600                       │
│                                                            │
│  ┌─────────┬─────────┬─────────┬─────────┬─────────┐     │
│  │ WG(0,0) │ WG(1,0) │ WG(2,0) │ ...     │WG(49,0) │     │
│  │16×16像素│16×16像素│16×16像素│         │16×16像素│     │
│  ├─────────┼─────────┼─────────┼─────────┼─────────┤     │
│  │ WG(0,1) │ WG(1,1) │ WG(2,1) │ ...     │WG(49,1) │     │
│  │16×16像素│16×16像素│16×16像素│         │16×16像素│     │
│  ├─────────┼─────────┼─────────┼─────────┼─────────┤     │
│  │   ...   │   ...   │   ...   │ ...     │   ...   │     │
│  ├─────────┼─────────┼─────────┼─────────┼─────────┤     │
│  │WG(0,37) │WG(1,37) │WG(2,37) │ ...     │WG(49,37)│     │
│  │16×16像素│16×16像素│16×16像素│         │16×16像素│     │
│  └─────────┴─────────┴─────────┴─────────┴─────────┘     │
│                                                            │
│  总计: 50 × 38 = 1900 个工作组                            │
│        1900 × 256 = 486,400 个并行计算单元                 │
└────────────────────────────────────────────────────────────┘
```

#### 3.4.2 渲染着色器

```wgsl
@compute @workgroup_size(16, 16)
fn main_render(@builtin(global_invocation_id) gid: vec3<u32>) {
    let px = gid.x;
    let py = gid.y;

    // 边界检查
    if (px < u32(CANVAS_W) && py < u32(CANVAS_H)) {
        render_pixel(&dom_result, &render_pixel_buf,
                     px, py, u32(CANVAS_W), u32(CANVAS_H));
    }
}

fn render_pixel(dom_tree, pixel_buf, px, py, canvas_w, canvas_h) {
    let x = f32(px);
    let y = f32(py);

    // 默认画布背景色
    var color = vec4<f32>(0.95, 0.95, 0.95, 1.0);

    // 遍历所有DOM节点
    for (var i: u32 = 0u; i < dom_tree.total_node; i++) {
        var node = dom_tree.nodes[i];

        // 跳过标记不渲染的节点
        if (node.style.skip_render) { continue; }

        let nx = node.style.layout_x;
        let ny = node.style.layout_y;
        let nw = node.style.content_w;
        let nh = node.style.content_h;

        // 像素是否在元素边界内
        if (x >= nx && x <= nx + nw &&
            y >= ny && y <= ny + nh) {

            // 绘制背景色
            if (node.style.bg_color.a > 0.0) {
                color = mix(color, node.style.bg_color,
                           node.style.bg_color.a);
            }

            // 绘制边框
            if (node.style.border_size > 0.0) {
                let b = node.style.border_size;
                if (x < nx + b || x > nx + nw - b ||
                    y < ny + b || y > ny + nh - b) {
                    color = node.style.border_color;
                }
            }

            // 绘制文本占位
            if (node.style.is_text_node) {
                let char_idx = u32((x - nx) / CHAR_WIDTH);
                if (char_idx < node.tag_name_len) {
                    color = mix(color, node.style.text_color, 0.9);
                }
            }

            // 绘制图片占位
            if (node.style.is_img_node) {
                let cx = nx + nw / 2.0;
                let cy = ny + nh / 2.0;
                let dist = length(vec2(x - cx, y - cy));
                if (dist < min(nw, nh) / 3.0) {
                    color = vec4<f32>(0.4, 0.6, 0.9, 1.0);
                }
            }
        }
    }

    // 写入像素缓冲区
    let idx = py * canvas_w + px;
    pixel_buf[idx] = color;
}
```

---

## 四、数据结构设计

### 4.1 常量定义

```wgsl
const MAX_HTML_LEN: u32 = 4096u;      // 最大HTML字节长度
const MAX_DOM_NODES: u32 = 512u;      // 最大DOM节点数量
const MAX_ATTRS: u32 = 16u;           // 单标签最大属性数量
const CANVAS_W: f32 = 800.0;          // 渲染画布宽度
const CANVAS_H: f32 = 600.0;          // 渲染画布高度
const CHAR_WIDTH: f32 = 8.0;          // 字符平均宽度
const LINE_HEIGHT: f32 = 18.0;        // 行高
```

### 4.2 结构体定义

```wgsl
// 属性结构
struct Attr {
    name_off: u32,    // 属性名字节偏移
    name_len: u32,    // 属性名长度
    val_off: u32,     // 属性值字节偏移
    val_len: u32,     // 属性值长度
}

// 内联样式结构
struct InlineStyle {
    // 尺寸
    width: f32,
    height: f32,
    // 外边距
    margin_left: f32,
    margin_top: f32,
    // 内边距
    padding_left: f32,
    padding_top: f32,
    // 布局坐标
    layout_x: f32,
    layout_y: f32,
    // 内容尺寸
    content_w: f32,
    content_h: f32,
    // 颜色
    bg_color: vec4<f32>,
    border_color: vec4<f32>,
    // 边框
    border_size: f32,
    border_radius: f32,
    // 文字
    font_size: f32,
    text_color: vec4<f32>,
    // 控制标志
    is_block: bool,
    skip_render: bool,
    is_text_node: bool,
    is_img_node: bool,
}

// DOM节点结构
struct DomNode {
    node_type: u32,
    tag_name_off: u32,
    tag_name_len: u32,
    parent_idx: u32,
    first_child: u32,
    next_sibling: u32,
    attrs: array<Attr, 16>,
    attr_count: u32,
    style: InlineStyle,
}

// DOM树根结构
struct DomRootTree {
    nodes: array<DomNode, 512>,
    total_node: u32,
    root_node_id: u32,
}
```

---

## 五、技术限制与注意事项

### 5.1 WebGPU兼容性

⚠️ **重要限制**

1. **浏览器支持**
   - 需要支持WebGPU的浏览器（Chrome 113+、Edge 113+、Safari 17+）
   - Firefox目前处于实验性支持阶段
   - 需要启用相关Feature Flag

2. **安全上下文**
   - 必须通过HTTPS或localhost访问
   - 文件协议(file://)可能不支持

3. **硬件要求**
   - 需要支持Vulkan/Metal/D3D12的GPU
   - 旧显卡可能不支持

### 5.2 性能注意事项

1. **缓冲区大小限制**
   ```javascript
   // 当前配置：800×600×4字节 = 1.92MB像素缓冲区
   const pixelBufferSize = 800 * 600 * 16;  // RGBA 32bit float

   // HTML缓冲区：4096×4字节 = 16KB
   const htmlBufferSize = 4096 * 4;
   ```

2. **计算资源限制**
   - 单个存储缓冲区最大512MB
   - 单次dispatch最多65535个工作组
   - WGSL不支持动态内存分配

3. **内存布局**
   - 需要精确计算结构体内存布局
   - 结构体对齐可能导致实际大小偏差
   - 建议使用固定大小数组而非动态分配

### 5.3 WGSL语言限制

1. **控制流限制**
   ```wgsl
   // ⚠️ 不支持动态continue/break
   // ⚠️ switch语句有限制

   // ✓ 推荐：使用简单for循环
   for (var i = 0u; i < count; i++) {
       // 固定迭代次数
   }
   ```

2. **函数参数限制**
   ```wgsl
   // ⚠️ 不能返回可变大小数组
   // ⚠️ 结构体不能包含可变大小成员

   // ✓ 使用ptr<storage>传递大型数据
   fn process(source: ptr<storage, array<u32>, read_write>) {
       // ...
   }
   ```

3. **纹理采样限制**
   ```wgsl
   // ⚠️ 当前实现不支持真实纹理采样
   // 图片渲染仅为占位符（圆形/矩形）

   // 未来支持需要：
   // 1. 图片数据编码上传
   // 2. 创建采样器纹理
   // 3. 使用textureSample读取
   ```

### 5.4 渲染限制

1. **文字渲染**
   - 当前仅支持占位符渲染
   - 不支持字体纹理采样
   - 无法渲染真实字符字形

2. **图片渲染**
   - 当前仅支持圆形占位符
   - 不支持纹理采样
   - 无法加载外部图片资源

3. **布局限制**
   - 仅支持block流式布局
   - 不支持flex/grid布局
   - 不支持position定位
   - 不支持z-index层叠

4. **样式限制**
   ```css
   /* 已支持 */
   width: 200px;
   height: 100px;
   background-color: #ff0000;
   color: #ffffff;
   font-size: 14px;
   border-radius: 8px;
   margin-left: 10px;
   margin-top: 10px;
   padding-left: 5px;
   padding-top: 5px;

   /* 暂不支持 */
   display: flex;
   position: absolute;
   z-index: 10;
   box-shadow: 0 2px 4px rgba(0,0,0,0.5);
   opacity: 0.5;
   transform: rotate(45deg);
   /* 等 */
   ```

---

## 六、调试与开发指南

### 6.1 常见错误排查

1. **"WebGPU not supported"**
   - 检查浏览器是否支持WebGPU
   - 确认通过HTTPS或localhost访问

2. **"Failed to execute 'mapAsync'"**
   - 缓冲区已被映射但未解除
   - 添加`unmap()`调用
   - 等待GPU命令完成后再读取

3. **渲染结果不正确**
   - 检查HTML语法是否正确
   - 验证CSS属性名拼写
   - 检查像素值是否合理

### 6.2 调试技巧

```javascript
// 添加日志输出
async renderHTML(html) {
    console.log('Input HTML:', html);
    console.log('HTML bytes:', new TextEncoder().encode(html));

    // ... 执行渲染 ...

    console.log('Pixel buffer size:', pixels.length);
    console.log('First pixel:', pixels[0]);
}
```

### 6.3 性能分析

```javascript
// 使用timestamp分析性能
async renderHTML(html) {
    const start = performance.now();

    // ... 渲染代码 ...

    const end = performance.now();
    console.log(`Render time: ${end - start}ms`);
}
```

---

## 七、扩展方向

### 7.1 短期可实现

1. **增强CSS支持**
   - rgb/rgba/hsl颜色格式
   - margin/padding四边支持
   - border完整属性
   - 字体粗细、斜体

2. **文本渲染**
   - 预渲染字体图集
   - 字符到字形映射
   - 基础文本换行

3. **布局增强**
   - 行内块布局
   - 居中/对齐支持
   - 百分比尺寸

### 7.2 中期目标

4. **真实图片渲染**
   - 图片数据编码上传
   - GPU纹理采样
   - 图片缩放裁剪

5. **交互功能**
   - 鼠标点击检测
   - 悬停效果
   - 简单动画

6. **性能优化**
   - 脏区域渲染
   - 增量更新
   - 多实例渲染

### 7.3 长期愿景

7. **完整CSS支持**
   - Flexbox布局引擎
   - CSS Grid布局
   - 绝对/相对定位

8. **DOM操作API**
   - JavaScript查询DOM
   - 动态更新样式
   - 事件系统

9. **应用场景**
   - 小程序渲染引擎
   - 可视化图表
   - 游戏UI系统
   - 富文本编辑器

---

## 八、API参考

### 8.1 WGSLRenderer 类

```javascript
class WGSLRenderer {
    // 初始化渲染器
    async init(canvas: HTMLCanvasElement): Promise<void>

    // 渲染HTML
    async renderHTML(html: string): Promise<void>

    // 销毁资源
    destroy(): void
}
```

### 8.2 使用示例

```javascript
import { WGSLRenderer } from './js/renderer.js';

const renderer = new WGSLRenderer();
await renderer.init(document.getElementById('canvas'));

const html = `
<div style="background-color:#e8f4fd; padding:10px;">
    <div style="color:#333; font-size:20px;">Hello World</div>
</div>
`;

await renderer.renderHTML(html);
```

---

## 九、文件结构

```
pure-wsgl-randering/
├── index.html                 # 主入口页面
├── README.md                  # 项目简介
├── ARCHITECTURE.md            # 本文档
├── WGSL 基于分词能力实现...md   # 原始技术文档
├── IMPLEMENTATION.md          # 实施步骤
├── wgsl/                     # WGSL着色器模块
│   ├── constants.wgsl        # 常量和结构体
│   ├── utils.wgsl            # 工具函数
│   ├── html_parser.wgsl      # HTML解析
│   ├── css_parser.wgsl       # CSS解析
│   ├── layout.wgsl           # 布局引擎
│   ├── renderer.wgsl         # 渲染器
│   └── main.wgsl             # 完整合并版
└── js/
    └── renderer.js           # WebGPU驱动
```

---

## 十、总结

本项目展示了如何利用WebGPU/WGSL实现全链路GPU渲染的可能性。虽然目前功能相对基础，但证明了在GPU上运行复杂解析逻辑的可行性。随着WebGPU标准的成熟和硬件能力的提升，这种架构有望在性能敏感的场景中发挥重要作用。

关键技术要点：
- ✅ GPU端词法分析和DOM构建
- ✅ 并行像素级渲染
- ✅ 流式布局算法
- ✅ 内联CSS解析
- ⚠️ 限于当前WGSL语言的限制

未来发展方向将聚焦于完善CSS支持、文本渲染和布局引擎，最终目标是构建一个高性能的GPU端UI渲染系统。
