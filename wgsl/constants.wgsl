const MAX_HTML_LEN: u32 = 4096u;
const MAX_DOM_NODES: u32 = 512u;
const MAX_ATTRS: u32 = 16u;
const MAX_TOKEN_PER_TEXT: u32 = 64u;
const CANVAS_W: f32 = 800.0;
const CANVAS_H: f32 = 600.0;
const FONT_SIZE_DEFAULT: f32 = 14.0;
const CHAR_WIDTH: f32 = 8.0;
const LINE_HEIGHT: f32 = 18.0;

enum NodeType {
  ELEM = 0,
  TEXT = 1,
  IMAGE = 2
}

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

struct ParseContext {
  html_ptr: u32,
  html_len: u32,
  node_stack: array<u32, 64>,
  stack_ptr: u32,
  in_comment: bool,
  in_tag: bool,
  current_node_idx: u32
}
