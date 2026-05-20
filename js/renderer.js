const SHADER_CODE = `
const MAX_HTML_LEN: u32 = 4096u;
const MAX_DOM_NODES: u32 = 512u;
const MAX_ATTRS: u32 = 16u;
const MAX_TOKEN_PER_TEXT: u32 = 64u;
const CANVAS_W: f32 = 800.0;
const CANVAS_H: f32 = 600.0;
const FONT_SIZE_DEFAULT: f32 = 14.0;
const CHAR_WIDTH: f32 = 8.0;
const LINE_HEIGHT: f32 = 18.0;

struct Attr {
  name_off: u32,
  name_len: u32,
  val_off: u32,
  val_len: u32
}

struct InlineStyle {
  width: f32,
  height: f32,
  margin_left: f32,
  margin_top: f32,
  padding_left: f32,
  padding_top: f32,
  layout_x: f32,
  layout_y: f32,
  content_w: f32,
  content_h: f32,
  bg_color: vec4<f32>,
  border_color: vec4<f32>,
  border_size: f32,
  border_radius: f32,
  font_size: f32,
  text_color: vec4<f32>,
  is_block: u32,
  skip_render: u32,
  is_text_node: u32,
  is_img_node: u32
}

struct DomNode {
  node_type: u32,
  tag_name_off: u32,
  tag_name_len: u32,
  parent_idx: u32,
  first_child: u32,
  next_sibling: u32,
  attrs: array<Attr, 16>,
  attr_count: u32,
  style: InlineStyle
}

struct DomRootTree {
  nodes: array<DomNode, 512>,
  total_node: u32,
  root_node_id: u32
}

@group(0) @binding(0) var<storage, read_write> html_source: array<u32>;
@group(0) @binding(1) var<storage, read_write> dom_result: DomRootTree;
@group(0) @binding(2) var<storage, read_write> render_pixel_buf: array<vec4<f32>>;

fn is_blank_char(c: u32) -> bool {
  return c == 32u || c == 9u || c == 10u || c == 13u;
}

fn hex_to_int(c: u32) -> u32 {
  if (c >= 48u && c <= 57u) { return c - 48u; }
  if (c >= 97u && c <= 102u) { return c - 97u + 10u; }
  if (c >= 65u && c <= 70u) { return c - 65u + 10u; }
  return 0u;
}

fn parse_css_px(source: ptr<storage, array<u32>, read_write>, start: u32, end: u32) -> f32 {
  var result: f32 = 0.0;
  for (var i: u32 = start; i < end; i++) {
    let c = (*source)[i];
    if (c >= 48u && c <= 57u) {
      result = result * 10.0 + f32(c - 48u);
    } else if (c == 112u || c == 120u) {
      break;
    }
  }
  return result;
}

fn css_color_to_rgba(source: ptr<storage, array<u32>, read_write>, start: u32, end: u32) -> vec4<f32> {
  var color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
  if (end - start >= 7u && (*source)[start] == 35u) {
    let r1 = hex_to_int((*source)[start + 1]);
    let r2 = hex_to_int((*source)[start + 2]);
    let g1 = hex_to_int((*source)[start + 3]);
    let g2 = hex_to_int((*source)[start + 4]);
    let b1 = hex_to_int((*source)[start + 5]);
    let b2 = hex_to_int((*source)[start + 6]);
    color.r = f32(r1 * 16 + r2) / 255.0;
    color.g = f32(g1 * 16 + g2) / 255.0;
    color.b = f32(b1 * 16 + b2) / 255.0;
  }
  return color;
}

fn text_content_tokenize(source: ptr<storage, array<u32>, read_write>, text_s: u32, text_e: u32) -> vec2<f32> {
  var char_count: u32 = 0u;
  var line_count: u32 = 1u;
  for (var i: u32 = text_s; i < text_e; i++) {
    let c = (*source)[i];
    if (c == 10u) {
      line_count += 1u;
    } else if (!is_blank_char(c)) {
      char_count += 1u;
    }
  }
  return vec2<f32>(f32(char_count) * CHAR_WIDTH, f32(line_count) * LINE_HEIGHT);
}

fn init_style() -> InlineStyle {
  var s: InlineStyle;
  s.width = 0.0;
  s.height = 0.0;
  s.margin_left = 0.0;
  s.margin_top = 0.0;
  s.padding_left = 0.0;
  s.padding_top = 0.0;
  s.layout_x = 0.0;
  s.layout_y = 0.0;
  s.content_w = 0.0;
  s.content_h = 0.0;
  s.bg_color = vec4<f32>(1.0, 1.0, 1.0, 0.0);
  s.border_color = vec4<f32>(0.0, 0.0, 0.0, 0.0);
  s.border_size = 0.0;
  s.border_radius = 0.0;
  s.font_size = FONT_SIZE_DEFAULT;
  s.text_color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
  s.is_block = 1u;
  s.skip_render = 0u;
  s.is_text_node = 0u;
  s.is_img_node = 0u;
  return s;
}

fn create_dom_node(
  dom_tree: ptr<storage, DomRootTree, read_write>,
  node_type_val: u32,
  parent_idx_val: u32
) -> u32 {
  let idx = (*dom_tree).total_node;
  if (idx >= 512u) { return idx; }

  var node: DomNode;
  node.node_type = node_type_val;
  node.tag_name_off = 0u;
  node.tag_name_len = 0u;
  node.parent_idx = parent_idx_val;
  node.first_child = 512u;
  node.next_sibling = 512u;
  node.attr_count = 0u;
  node.style = init_style();

  if (parent_idx_val < 512u) {
    if ((*dom_tree).nodes[parent_idx_val].first_child == 512u) {
      (*dom_tree).nodes[parent_idx_val].first_child = idx;
    } else {
      var sibling_idx = (*dom_tree).nodes[parent_idx_val].first_child;
      while ((*dom_tree).nodes[sibling_idx].next_sibling != 512u) {
        sibling_idx = (*dom_tree).nodes[sibling_idx].next_sibling;
      }
      (*dom_tree).nodes[sibling_idx].next_sibling = idx;
    }
  }

  (*dom_tree).nodes[idx] = node;
  (*dom_tree).total_node += 1u;
  return idx;
}

fn is_blank_text(source: ptr<storage, array<u32>, read_write>, s: u32, e: u32) -> bool {
  for (var i: u32 = s; i < e; i++) {
    if (!is_blank_char((*source)[i])) {
      return false;
    }
  }
  return true;
}

fn parse_tag_attributes(
  source: ptr<storage, array<u32>, read_write>,
  start: u32,
  end: u32,
  dom_tree: ptr<storage, DomRootTree, read_write>,
  node_idx: u32
) {
  var ptr = start;
  var attr_count = 0u;

  while (ptr < end && attr_count < 16u) {
    while (ptr < end && is_blank_char((*source)[ptr])) { ptr += 1u; }
    if (ptr >= end) { break; }

    let attr_name_start = ptr;
    while (ptr < end && !is_blank_char((*source)[ptr]) && (*source)[ptr] != 61u) { ptr += 1u; }
    let attr_name_end = ptr;

    var attr_val_start = ptr;
    var attr_val_end = ptr;

    if (ptr < end && (*source)[ptr] == 61u) {
      ptr += 1u;
      var quote_char = 0u;
      if (ptr < end && ((*source)[ptr] == 34u || (*source)[ptr] == 39u)) {
        quote_char = (*source)[ptr];
        ptr += 1u;
        attr_val_start = ptr;
        while (ptr < end && (*source)[ptr] != quote_char) { ptr += 1u; }
        attr_val_end = ptr;
        if (ptr < end) { ptr += 1u; }
      } else {
        attr_val_start = ptr;
        while (ptr < end && !is_blank_char((*source)[ptr])) { ptr += 1u; }
        attr_val_end = ptr;
      }
    }

    if (attr_name_end > attr_name_start) {
      (*dom_tree).nodes[node_idx].attrs[attr_count].name_off = attr_name_start;
      (*dom_tree).nodes[node_idx].attrs[attr_count].name_len = attr_name_end - attr_name_start;
      (*dom_tree).nodes[node_idx].attrs[attr_count].val_off = attr_val_start;
      (*dom_tree).nodes[node_idx].attrs[attr_count].val_len = attr_val_end - attr_val_start;
      (*dom_tree).nodes[node_idx].attr_count += 1u;
      attr_count += 1u;
    }
  }
}

fn parse_html(
  html_source: ptr<storage, array<u32>, read_write>,
  html_len: u32,
  dom_tree: ptr<storage, DomRootTree, read_write>
) {
  (*dom_tree).total_node = 0u;
  (*dom_tree).root_node_id = create_dom_node(dom_tree, 0u, 512u);

  var node_stack: array<u32, 64>;
  var stack_ptr = 1u;
  node_stack[0] = (*dom_tree).root_node_id;
  var in_comment = false;
  var in_tag = false;
  var html_ptr = 0u;
  var text_start = 512u;
  var tag_start = 512u;

  while (html_ptr < html_len) {
    let c = (*html_source)[html_ptr];

    if (in_comment) {
      if (html_ptr + 2u < html_len &&
          (*html_source)[html_ptr] == 45u &&
          (*html_source)[html_ptr + 1u] == 45u &&
          (*html_source)[html_ptr + 2u] == 62u) {
        in_comment = false;
        html_ptr += 3u;
        continue;
      }
      html_ptr += 1u;
      continue;
    }

    if (c == 60u) {
      if (text_start != 512u) {
        let is_blank = is_blank_text(html_source, text_start, html_ptr);
        if (!is_blank) {
          let text_idx = create_dom_node(dom_tree, 1u, node_stack[stack_ptr - 1u]);
          (*dom_tree).nodes[text_idx].tag_name_off = text_start;
          (*dom_tree).nodes[text_idx].tag_name_len = html_ptr - text_start;
          (*dom_tree).nodes[text_idx].style.is_text_node = 1u;
          let size = text_content_tokenize(html_source, text_start, html_ptr);
          (*dom_tree).nodes[text_idx].style.content_w = size.x;
          (*dom_tree).nodes[text_idx].style.content_h = size.y;
        }
        text_start = 512u;
      }

      if (html_ptr + 3u < html_len &&
          (*html_source)[html_ptr + 1u] == 33u &&
          (*html_source)[html_ptr + 2u] == 45u &&
          (*html_source)[html_ptr + 3u] == 45u) {
        in_comment = true;
        html_ptr += 4u;
        continue;
      }

      tag_start = html_ptr + 1u;
      in_tag = true;
      html_ptr += 1u;
      continue;
    }

    if (c == 62u && in_tag) {
      let is_close = (*html_source)[tag_start] == 47u;
      let tag_real_start = select(tag_start, tag_start + 1u, is_close);
      let tag_end = html_ptr;

      if (!is_close) {
        var tag_name_end = tag_real_start;
        while (tag_name_end < tag_end && !is_blank_char((*html_source)[tag_name_end]) && (*html_source)[tag_name_end] != 47u) {
          tag_name_end += 1u;
        }

        let is_self_close = (*html_source)[tag_end - 1u] == 47u;
        let tag_len = tag_name_end - tag_real_start;

        var is_img = false;
        if (tag_len == 3u) {
          is_img = (*html_source)[tag_real_start] == 105u &&
                   (*html_source)[tag_real_start + 1u] == 109u &&
                   (*html_source)[tag_real_start + 2u] == 103u;
        }

        let node_type = select(0u, 2u, is_img);
        let new_idx = create_dom_node(dom_tree, node_type, node_stack[stack_ptr - 1u]);

        (*dom_tree).nodes[new_idx].tag_name_off = tag_real_start;
        (*dom_tree).nodes[new_idx].tag_name_len = tag_len;

        if (is_img) {
          (*dom_tree).nodes[new_idx].style.is_img_node = 1u;
          (*dom_tree).nodes[new_idx].style.width = 100.0;
          (*dom_tree).nodes[new_idx].style.height = 100.0;
        }

        parse_tag_attributes(html_source, tag_name_end, select(tag_end, tag_end - 1u, is_self_close), dom_tree, new_idx);

        if (!is_self_close) {
          node_stack[stack_ptr] = new_idx;
          stack_ptr += 1u;
        }
      } else {
        if (stack_ptr > 1u) {
          stack_ptr -= 1u;
        }
      }

      in_tag = false;
      tag_start = 512u;
      html_ptr += 1u;
      continue;
    }

    if (!in_tag && text_start == 512u && !is_blank_char(c)) {
      text_start = html_ptr;
    }

    html_ptr += 1u;
  }
}

fn apply_style_property(
  source: ptr<storage, array<u32>, read_write>,
  key_s: u32, key_e: u32,
  val_s: u32, val_e: u32,
  node_idx: u32,
  dom_tree: ptr<storage, DomRootTree, read_write>
) {
  let key_len = key_e - key_s;

  if (key_len == 5u) {
    let c0 = (*source)[key_s];
    let c1 = (*source)[key_s + 1u];
    let c2 = (*source)[key_s + 2u];
    let c3 = (*source)[key_s + 3u];
    let c4 = (*source)[key_s + 4u];

    if (c0 == 119u && c1 == 105u && c2 == 100u && c3 == 116u && c4 == 104u) {
      (*dom_tree).nodes[node_idx].style.width = parse_css_px(source, val_s, val_e);
    } else if (c0 == 104u && c1 == 101u && c2 == 105u && c3 == 103u && c4 == 104u) {
      (*dom_tree).nodes[node_idx].style.height = parse_css_px(source, val_s, val_e);
    } else if (c0 == 99u && c1 == 111u && c2 == 108u && c3 == 111u && c4 == 114u) {
      (*dom_tree).nodes[node_idx].style.text_color = css_color_to_rgba(source, val_s, val_e);
    }
  }

  if (key_len == 9u) {
    let c0 = (*source)[key_s];
    let c1 = (*source)[key_s + 1u];
    let c2 = (*source)[key_s + 2u];
    let c3 = (*source)[key_s + 3u];
    let c4 = (*source)[key_s + 4u];
    let c5 = (*source)[key_s + 5u];
    let c6 = (*source)[key_s + 6u];
    let c7 = (*source)[key_s + 7u];
    let c8 = (*source)[key_s + 8u];

    if (c0 == 102u && c1 == 111u && c2 == 110u && c3 == 116u && c4 == 45u && c5 == 115u && c6 == 105u && c7 == 122u && c8 == 101u) {
      (*dom_tree).nodes[node_idx].style.font_size = parse_css_px(source, val_s, val_e);
    }
  }

  if (key_len >= 15u) {
    let c0 = (*source)[key_s];
    let c1 = (*source)[key_s + 1u];
    let c2 = (*source)[key_s + 2u];
    let c3 = (*source)[key_s + 3u];
    let c4 = (*source)[key_s + 4u];
    let c5 = (*source)[key_s + 5u];
    let c6 = (*source)[key_s + 6u];
    let c7 = (*source)[key_s + 7u];
    let c8 = (*source)[key_s + 8u];
    let c9 = (*source)[key_s + 9u];
    let c10 = (*source)[key_s + 10u];
    let c11 = (*source)[key_s + 11u];
    let c12 = (*source)[key_s + 12u];
    let c13 = (*source)[key_s + 13u];
    let c14 = (*source)[key_s + 14u];

    if (key_len == 16u) {
      let c15 = (*source)[key_s + 15u];
      if (c0 == 98u && c1 == 97u && c2 == 99u && c3 == 107u && c4 == 103u && c5 == 114u && c6 == 111u && c7 == 117u && c8 == 110u && c9 == 100u && c10 == 45u && c11 == 99u && c12 == 111u && c13 == 108u && c14 == 111u && c15 == 114u) {
        (*dom_tree).nodes[node_idx].style.bg_color = css_color_to_rgba(source, val_s, val_e);
      }
    }
  }

  if (key_len == 13u) {
    let c0 = (*source)[key_s];
    let c1 = (*source)[key_s + 1u];
    let c2 = (*source)[key_s + 2u];
    let c3 = (*source)[key_s + 3u];
    let c4 = (*source)[key_s + 4u];
    let c5 = (*source)[key_s + 5u];
    let c6 = (*source)[key_s + 6u];
    let c7 = (*source)[key_s + 7u];
    let c8 = (*source)[key_s + 8u];
    let c9 = (*source)[key_s + 9u];
    let c10 = (*source)[key_s + 10u];
    let c11 = (*source)[key_s + 11u];
    let c12 = (*source)[key_s + 12u];

    if (c0 == 98u && c1 == 111u && c2 == 114u && c3 == 100u && c4 == 101u && c5 == 114u && c6 == 45u && c7 == 114u && c8 == 97u && c9 == 100u && c10 == 105u && c11 == 117u && c12 == 115u) {
      (*dom_tree).nodes[node_idx].style.border_radius = parse_css_px(source, val_s, val_e);
    }
  }
}

fn parse_style_string(
  source: ptr<storage, array<u32>, read_write>,
  s: u32,
  e: u32,
  node_idx: u32,
  dom_tree: ptr<storage, DomRootTree, read_write>
) {
  var ptr = s;
  while (ptr < e) {
    while (ptr < e && is_blank_char((*source)[ptr])) { ptr += 1u; }
    let key_start = ptr;
    while (ptr < e && (*source)[ptr] != 58u && !is_blank_char((*source)[ptr])) { ptr += 1u; }
    let key_end = ptr;
    if (ptr < e && (*source)[ptr] == 58u) { ptr += 1u; }
    while (ptr < e && is_blank_char((*source)[ptr])) { ptr += 1u; }
    let val_start = ptr;
    while (ptr < e && (*source)[ptr] != 59u) { ptr += 1u; }
    let val_end = ptr;
    if (ptr < e && (*source)[ptr] == 59u) { ptr += 1u; }

    if (key_end > key_start && val_end > val_start) {
      apply_style_property(source, key_start, key_end, val_start, val_end, node_idx, dom_tree);
    }
  }
}

fn parse_inline_css(
  source: ptr<storage, array<u32>, read_write>,
  dom_tree: ptr<storage, DomRootTree, read_write>,
  node_idx: u32
) {
  for (var a: u32 = 0u; a < (*dom_tree).nodes[node_idx].attr_count; a++) {
    let attr_len = (*dom_tree).nodes[node_idx].attrs[a].name_len;
    let is_style = attr_len == 5u;
    if (is_style) {
      let name_off = (*dom_tree).nodes[node_idx].attrs[a].name_off;
      let match1 = (*source)[name_off] == 115u;
      let match2 = (*source)[name_off + 1u] == 116u;
      let match3 = (*source)[name_off + 2u] == 121u;
      let match4 = (*source)[name_off + 3u] == 108u;
      let match5 = (*source)[name_off + 4u] == 101u;
      if (match1 && match2 && match3 && match4 && match5) {
        let val_off = (*dom_tree).nodes[node_idx].attrs[a].val_off;
        let val_len = (*dom_tree).nodes[node_idx].attrs[a].val_len;
        parse_style_string(source, val_off, val_off + val_len, node_idx, dom_tree);
      }
    }
  }
}

fn parse_all_css(
  source: ptr<storage, array<u32>, read_write>,
  dom_tree: ptr<storage, DomRootTree, read_write>
) {
  for (var i: u32 = 0u; i < (*dom_tree).total_node; i++) {
    parse_inline_css(source, dom_tree, i);
  }
}

fn layout_iterative(
  dom_tree: ptr<storage, DomRootTree, read_write>
) {
  let root_id = (*dom_tree).root_node_id;
  (*dom_tree).nodes[root_id].style.layout_x = 10.0;
  (*dom_tree).nodes[root_id].style.layout_y = 10.0;
  (*dom_tree).nodes[root_id].style.content_w = CANVAS_W - 20.0;
  (*dom_tree).nodes[root_id].style.content_h = CANVAS_H - 20.0;

  var stack: array<u32, 64>;
  var stack_size: u32 = 0u;

  stack[0] = root_id;
  stack_size = 1u;

  while (stack_size > 0u) {
    stack_size = stack_size - 1u;
    var parent_idx = stack[stack_size];

    var current_x = (*dom_tree).nodes[parent_idx].style.layout_x + (*dom_tree).nodes[parent_idx].style.padding_left;
    var current_y = (*dom_tree).nodes[parent_idx].style.layout_y + (*dom_tree).nodes[parent_idx].style.padding_top;

    var child_idx = (*dom_tree).nodes[parent_idx].first_child;
    while (child_idx != 512u && child_idx < (*dom_tree).total_node) {
      if ((*dom_tree).nodes[child_idx].style.is_text_node != 0u) {
        if ((*dom_tree).nodes[child_idx].style.content_w <= 0.0 || (*dom_tree).nodes[child_idx].style.content_h <= 0.0) {
          (*dom_tree).nodes[child_idx].style.skip_render = 1u;
        }
      }

      if ((*dom_tree).nodes[child_idx].style.skip_render == 0u) {
        var child_w = select((*dom_tree).nodes[child_idx].style.content_w, (*dom_tree).nodes[child_idx].style.width, (*dom_tree).nodes[child_idx].style.width > 0.0);
        var child_h = select((*dom_tree).nodes[child_idx].style.content_h, (*dom_tree).nodes[child_idx].style.height, (*dom_tree).nodes[child_idx].style.height > 0.0);

        if (child_w <= 0.0) { child_w = 100.0; }
        if (child_h <= 0.0) { child_h = 20.0; }

        (*dom_tree).nodes[child_idx].style.content_w = child_w;
        (*dom_tree).nodes[child_idx].style.content_h = child_h;

        (*dom_tree).nodes[child_idx].style.layout_x = current_x + (*dom_tree).nodes[child_idx].style.margin_left;
        (*dom_tree).nodes[child_idx].style.layout_y = current_y + (*dom_tree).nodes[child_idx].style.margin_top;

        if ((*dom_tree).nodes[child_idx].style.is_block != 0u) {
          current_y += child_h + (*dom_tree).nodes[child_idx].style.margin_top + 8.0;
        } else {
          current_x += child_w + (*dom_tree).nodes[child_idx].style.margin_left + 4.0;
        }
      }

      if ((*dom_tree).nodes[child_idx].first_child != 512u && stack_size < 64u) {
        stack[stack_size] = child_idx;
        stack_size = stack_size + 1u;
      }

      child_idx = (*dom_tree).nodes[child_idx].next_sibling;
    }
  }
}

fn calculate_layout(
  dom_tree: ptr<storage, DomRootTree, read_write>
) {
  layout_iterative(dom_tree);
}

fn render_pixel(
  dom_tree: ptr<storage, DomRootTree, read_write>,
  pixel_buf: ptr<storage, array<vec4<f32>>, read_write>,
  px: u32,
  py: u32,
  canvas_w: u32,
  canvas_h: u32
) {
  let x = f32(px);
  let y = f32(py);
  var color = vec4<f32>(0.95, 0.95, 0.95, 1.0);

  for (var i: u32 = 0u; i < (*dom_tree).total_node; i++) {
    if ((*dom_tree).nodes[i].style.skip_render != 0u) { continue; }

    let nx = (*dom_tree).nodes[i].style.layout_x;
    let ny = (*dom_tree).nodes[i].style.layout_y;
    let nw = (*dom_tree).nodes[i].style.content_w;
    let nh = (*dom_tree).nodes[i].style.content_h;

    if (x >= nx && x <= nx + nw && y >= ny && y <= ny + nh) {
      if ((*dom_tree).nodes[i].style.bg_color.a > 0.0) {
        color = mix(color, (*dom_tree).nodes[i].style.bg_color, (*dom_tree).nodes[i].style.bg_color.a);
      }

      if ((*dom_tree).nodes[i].style.border_size > 0.0) {
        let border = (*dom_tree).nodes[i].style.border_size;
        if (x < nx + border || x > nx + nw - border ||
            y < ny + border || y > ny + nh - border) {
          if ((*dom_tree).nodes[i].style.border_color.a > 0.0) {
            color = mix(color, (*dom_tree).nodes[i].style.border_color, (*dom_tree).nodes[i].style.border_color.a);
          }
        }
      }

      if ((*dom_tree).nodes[i].style.is_text_node != 0u) {
        let in_bounds = x >= nx + 2.0 && x <= nx + nw - 2.0 &&
                        y >= ny + 2.0 && y <= ny + nh - 2.0;
        if (in_bounds) {
          let char_idx = u32((x - nx - 2.0) / CHAR_WIDTH);
          let text_off = (*dom_tree).nodes[i].tag_name_off;
          let text_len = (*dom_tree).nodes[i].tag_name_len;
          if (char_idx < text_len) {
            let line_y = u32((y - ny - 2.0) / LINE_HEIGHT);
            if (line_y < 2u) {
              color = mix(color, (*dom_tree).nodes[i].style.text_color, 0.9);
            }
          }
        }
      }

      if ((*dom_tree).nodes[i].style.is_img_node != 0u) {
        let cx = nx + nw / 2.0;
        let cy = ny + nh / 2.0;
        let dx = x - cx;
        let dy = y - cy;
        let dist = sqrt(dx * dx + dy * dy);
        if (dist < min(nw, nh) / 3.0) {
          color = mix(color, vec4<f32>(0.4, 0.6, 0.9, 1.0), 0.8);
        }
      }
    }
  }

  let idx = py * canvas_w + px;
  (*pixel_buf)[idx] = color;
}

@compute @workgroup_size(1)
fn main_parse() {
  let html_len = html_source[0];
  parse_html(&html_source, html_len, &dom_result);
  parse_all_css(&html_source, &dom_result);
  calculate_layout(&dom_result);
}

@compute @workgroup_size(16, 16)
fn main_render(
  @builtin(global_invocation_id) gid: vec3<u32>
) {
  let px = gid.x;
  let py = gid.y;

  if (px < u32(CANVAS_W) && py < u32(CANVAS_H)) {
    render_pixel(&dom_result, &render_pixel_buf, px, py, u32(CANVAS_W), u32(CANVAS_H));
  }
}
`;

export class WGSLRenderer {
  constructor() {
    this.device = null;
    this.canvas = null;
    this.context = null;
    this.htmlBuffer = null;
    this.domBuffer = null;
    this.pixelBuffer = null;
    this.readPixelBuffer = null;
    this.parsePipeline = null;
    this.renderPipeline = null;
    this.bindGroup = null;
  }

  async init(canvas) {
    this.canvas = canvas;

    if (!navigator.gpu) {
      throw new Error('WebGPU not supported');
    }

    const adapter = await navigator.gpu.requestAdapter();
    if (!adapter) {
      throw new Error('No GPU adapter found');
    }

    this.device = await adapter.requestDevice();
    this.context = canvas.getContext('webgpu');
    const format = navigator.gpu.getPreferredCanvasFormat();
    this.context.configure({
      device: this.device,
      format: format
    });

    await this.createBuffers();
    await this.createPipelines();
  }

  async createBuffers() {
    this.htmlBuffer = this.device.createBuffer({
      size: 4096 * 4,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
    });

    const domNodeSize = (4 + 4 + 4 + 4 + 4 + 16 * (4 * 4) + 4 + (4 * 10 + 4 * 4 + 1)) * 512 + 8;
    this.domBuffer = this.device.createBuffer({
      size: domNodeSize,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST
    });

    const pixelBufferSize = 800 * 600 * 16;
    this.pixelBuffer = this.device.createBuffer({
      size: pixelBufferSize,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC
    });

    this.readPixelBuffer = this.device.createBuffer({
      size: pixelBufferSize,
      usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ
    });
  }

  async createPipelines() {
    const shaderModule = this.device.createShaderModule({
      code: SHADER_CODE
    });

    const bindGroupLayout = this.device.createBindGroupLayout({
      entries: [
        {
          binding: 0,
          visibility: GPUShaderStage.COMPUTE,
          buffer: { type: 'storage' }
        },
        {
          binding: 1,
          visibility: GPUShaderStage.COMPUTE,
          buffer: { type: 'storage' }
        },
        {
          binding: 2,
          visibility: GPUShaderStage.COMPUTE,
          buffer: { type: 'storage' }
        }
      ]
    });

    const pipelineLayout = this.device.createPipelineLayout({
      bindGroupLayouts: [bindGroupLayout]
    });

    this.parsePipeline = this.device.createComputePipeline({
      layout: pipelineLayout,
      compute: {
        module: shaderModule,
        entryPoint: 'main_parse'
      }
    });

    this.renderPipeline = this.device.createComputePipeline({
      layout: pipelineLayout,
      compute: {
        module: shaderModule,
        entryPoint: 'main_render'
      }
    });

    this.bindGroup = this.device.createBindGroup({
      layout: bindGroupLayout,
      entries: [
        {
          binding: 0,
          resource: { buffer: this.htmlBuffer }
        },
        {
          binding: 1,
          resource: { buffer: this.domBuffer }
        },
        {
          binding: 2,
          resource: { buffer: this.pixelBuffer }
        }
      ]
    });
  }

  async renderHTML(html) {
    if (this.readPixelBuffer.mapState === 'mapped') {
      this.readPixelBuffer.unmap();
    }

    const encoder = new TextEncoder();
    const htmlBytes = encoder.encode(html);
    const htmlData = new Uint32Array(4096);
    htmlData[0] = Math.min(htmlBytes.length, 4095);
    for (let i = 0; i < htmlData[0]; i++) {
      htmlData[i + 1] = htmlBytes[i];
    }

    this.device.queue.writeBuffer(this.htmlBuffer, 0, htmlData.buffer);

    const commandEncoder = this.device.createCommandEncoder();

    const parsePass = commandEncoder.beginComputePass();
    parsePass.setPipeline(this.parsePipeline);
    parsePass.setBindGroup(0, this.bindGroup);
    parsePass.dispatchWorkgroups(1);
    parsePass.end();

    const renderPass = commandEncoder.beginComputePass();
    renderPass.setPipeline(this.renderPipeline);
    renderPass.setBindGroup(0, this.bindGroup);
    renderPass.dispatchWorkgroups(Math.ceil(800 / 16), Math.ceil(600 / 16));
    renderPass.end();

    commandEncoder.copyBufferToBuffer(
      this.pixelBuffer,
      0,
      this.readPixelBuffer,
      0,
      800 * 600 * 16
    );

    const commandBuffer = commandEncoder.finish();
    this.device.queue.submit([commandBuffer]);

    await this.device.queue.onSubmittedWorkDone();
    await this.readPixelBuffer.mapAsync(GPUMapMode.READ);
    const pixels = new Float32Array(this.readPixelBuffer.getMappedRange());

    const ctx = this.canvas.getContext('2d');
    const imgData = ctx.createImageData(800, 600);
    for (let i = 0; i < 800 * 600; i++) {
      imgData.data[i * 4] = Math.floor(pixels[i * 4] * 255);
      imgData.data[i * 4 + 1] = Math.floor(pixels[i * 4 + 1] * 255);
      imgData.data[i * 4 + 2] = Math.floor(pixels[i * 4 + 2] * 255);
      imgData.data[i * 4 + 3] = 255;
    }
    ctx.putImageData(imgData, 0, 0);

    this.readPixelBuffer.unmap();
  }
}
