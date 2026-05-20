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
  is_block: bool,
  skip_render: bool,
  is_text_node: bool,
  is_img_node: bool
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
  s.is_block = true;
  s.skip_render = false;
  s.is_text_node = false;
  s.is_img_node = false;
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
    var parent_node = &(*dom_tree).nodes[parent_idx_val];
    if ((*parent_node).first_child == 512u) {
      (*parent_node).first_child = idx;
    } else {
      var sibling_idx = (*parent_node).first_child;
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
      var node = &(*dom_tree).nodes[node_idx];
      var attr = &(*node).attrs[attr_count];
      (*attr).name_off = attr_name_start;
      (*attr).name_len = attr_name_end - attr_name_start;
      (*attr).val_off = attr_val_start;
      (*attr).val_len = attr_val_end - attr_val_start;
      (*node).attr_count += 1u;
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
          var text_node = &(*dom_tree).nodes[text_idx];
          (*text_node).tag_name_off = text_start;
          (*text_node).tag_name_len = html_ptr - text_start;
          (*text_node).style.is_text_node = true;
          let size = text_content_tokenize(html_source, text_start, html_ptr);
          (*text_node).style.content_w = size.x;
          (*text_node).style.content_h = size.y;
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

        var new_node = &(*dom_tree).nodes[new_idx];
        (*new_node).tag_name_off = tag_real_start;
        (*new_node).tag_name_len = tag_len;

        if (is_img) {
          (*new_node).style.is_img_node = true;
          (*new_node).style.width = 100.0;
          (*new_node).style.height = 100.0;
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
  style: ptr<function, InlineStyle>
) {
  let key_len = key_e - key_s;

  if (key_len == 5u) {
    let c0 = (*source)[key_s];
    let c1 = (*source)[key_s + 1u];
    let c2 = (*source)[key_s + 2u];
    let c3 = (*source)[key_s + 3u];
    let c4 = (*source)[key_s + 4u];

    if (c0 == 119u && c1 == 105u && c2 == 100u && c3 == 116u && c4 == 104u) {
      (*style).width = parse_css_px(source, val_s, val_e);
    } else if (c0 == 104u && c1 == 101u && c2 == 105u && c3 == 103u && c4 == 104u) {
      (*style).height = parse_css_px(source, val_s, val_e);
    } else if (c0 == 99u && c1 == 111u && c2 == 108u && c3 == 111u && c4 == 114u) {
      (*style).text_color = css_color_to_rgba(source, val_s, val_e);
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
      (*style).font_size = parse_css_px(source, val_s, val_e);
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
        (*style).bg_color = css_color_to_rgba(source, val_s, val_e);
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
      (*style).border_radius = parse_css_px(source, val_s, val_e);
    }
  }
}

fn parse_style_string(
  source: ptr<storage, array<u32>, read_write>,
  s: u32,
  e: u32,
  style: ptr<function, InlineStyle>
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
      apply_style_property(source, key_start, key_end, val_start, val_end, style);
    }
  }
}

fn parse_inline_css(
  source: ptr<storage, array<u32>, read_write>,
  dom_tree: ptr<storage, DomRootTree, read_write>,
  node_idx: u32
) {
  var node = &(*dom_tree).nodes[node_idx];
  var style = &(*node).style;

  for (var a: u32 = 0u; a < (*node).attr_count; a++) {
    var attr = &(*node).attrs[a];
    let is_style = (*attr).name_len == 5u;
    if (is_style) {
      let match1 = (*source)[(*attr).name_off] == 115u;
      let match2 = (*source)[(*attr).name_off + 1u] == 116u;
      let match3 = (*source)[(*attr).name_off + 2u] == 121u;
      let match4 = (*source)[(*attr).name_off + 3u] == 108u;
      let match5 = (*source)[(*attr).name_off + 4u] == 101u;
      if (match1 && match2 && match3 && match4 && match5) {
        parse_style_string(source, (*attr).val_off, (*attr).val_off + (*attr).val_len, style);
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

fn layout_node_children(
  dom_tree: ptr<storage, DomRootTree, read_write>,
  parent_idx: u32,
  visited: ptr<function, array<bool, 512>>
) {
  var parent = &(*dom_tree).nodes[parent_idx];
  if ((*visited)[parent_idx]) { return; }
  (*visited)[parent_idx] = true;

  var current_x = (*parent).style.layout_x + (*parent).style.padding_left;
  var current_y = (*parent).style.layout_y + (*parent).style.padding_top;

  var child_idx = (*parent).first_child;
  while (child_idx != 512u && child_idx < (*dom_tree).total_node) {
    var child = &(*dom_tree).nodes[child_idx];

    if ((*child).style.is_text_node) {
      if ((*child).style.content_w <= 0.0 || (*child).style.content_h <= 0.0) {
        (*child).style.skip_render = true;
      }
    }

    if (!(*child).style.skip_render) {
      var child_w = select((*child).style.content_w, (*child).style.width, (*child).style.width > 0.0);
      var child_h = select((*child).style.content_h, (*child).style.height, (*child).style.height > 0.0);

      if (child_w <= 0.0) { child_w = 100.0; }
      if (child_h <= 0.0) { child_h = 20.0; }

      (*child).style.content_w = child_w;
      (*child).style.content_h = child_h;

      (*child).style.layout_x = current_x + (*child).style.margin_left;
      (*child).style.layout_y = current_y + (*child).style.margin_top;

      if ((*child).style.is_block) {
        current_y += child_h + (*child).style.margin_top + 8.0;
      } else {
        current_x += child_w + (*child).style.margin_left + 4.0;
      }
    }

    if ((*child).first_child != 512u) {
      layout_node_children(dom_tree, child_idx, visited);
    }

    child_idx = (*child).next_sibling;
  }
}

fn calculate_layout(
  dom_tree: ptr<storage, DomRootTree, read_write>
) {
  var root = &(*dom_tree).nodes[(*dom_tree).root_node_id];
  (*root).style.layout_x = 10.0;
  (*root).style.layout_y = 10.0;
  (*root).style.content_w = CANVAS_W - 20.0;
  (*root).style.content_h = CANVAS_H - 20.0;

  var visited: array<bool, 512>;
  for (var i: u32 = 0u; i < 512u; i++) {
    visited[i] = false;
  }

  layout_node_children(dom_tree, (*dom_tree).root_node_id, &visited);
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
    var node = &(*dom_tree).nodes[i];
    if ((*node).style.skip_render) { continue; }

    let nx = (*node).style.layout_x;
    let ny = (*node).style.layout_y;
    let nw = (*node).style.content_w;
    let nh = (*node).style.content_h;

    if (x >= nx && x <= nx + nw && y >= ny && y <= ny + nh) {
      if ((*node).style.bg_color.a > 0.0) {
        color = mix(color, (*node).style.bg_color, (*node).style.bg_color.a);
      }

      if ((*node).style.border_size > 0.0) {
        let border = (*node).style.border_size;
        if (x < nx + border || x > nx + nw - border ||
            y < ny + border || y > ny + nh - border) {
          if ((*node).style.border_color.a > 0.0) {
            color = mix(color, (*node).style.border_color, (*node).style.border_color.a);
          }
        }
      }

      if ((*node).style.is_text_node) {
        let in_bounds = x >= nx + 2.0 && x <= nx + nw - 2.0 &&
                        y >= ny + 2.0 && y <= ny + nh - 2.0;
        if (in_bounds) {
          let char_idx = u32((x - nx - 2.0) / CHAR_WIDTH);
          let text_off = (*node).tag_name_off;
          let text_len = (*node).tag_name_len;
          if (char_idx < text_len) {
            let line_y = u32((y - ny - 2.0) / LINE_HEIGHT);
            if (line_y < 2u) {
              color = mix(color, (*node).style.text_color, 0.9);
            }
          }
        }
      }

      if ((*node).style.is_img_node) {
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
