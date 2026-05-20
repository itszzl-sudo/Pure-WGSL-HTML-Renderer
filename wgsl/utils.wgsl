fn is_blank_char(c: u32) -> bool {
  return c == 32u || c == 9u || c == 10u || c == 13u;
}

fn is_token_sep(c: u32) -> bool {
  let seps = array<u32, 14>(32u, 44u, 59u, 58u, 33u, 63u, 46u, 33u, 40u, 41u, 91u, 93u, 123u, 125u);
  for (var i: u32 = 0u; i < 14u; i++) {
    if (c == seps[i]) {
      return true;
    }
  }
  return false;
}

fn byte_str_match(source: ptr<storage, array<u32>, read_write>, start: u32, end: u32, target: ptr<storage, array<u32>, read_write>, t_len: u32) -> bool {
  if (end - start != t_len) {
    return false;
  }
  for (var i: u32 = 0u; i < t_len; i++) {
    if ((*source)[start + i] != (*target)[i]) {
      return false;
    }
  }
  return true;
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

fn hex_to_int(c: u32) -> u32 {
  if (c >= 48u && c <= 57u) { return c - 48u; }
  if (c >= 97u && c <= 102u) { return c - 97u + 10u; }
  if (c >= 65u && c <= 70u) { return c - 65u + 10u; }
  return 0u;
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

fn get_image_real_size(node: DomNode) -> vec2<f32> {
  var w = node.style.width;
  var h = node.style.height;
  if (w <= 0.0) { w = 100.0; }
  if (h <= 0.0) { h = 100.0; }
  return vec2<f32>(w, h);
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
