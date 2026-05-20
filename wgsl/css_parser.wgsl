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

  if (key_len == 15u) {
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

    if (c0 == 98u && c1 == 97u && c2 == 99u && c3 == 107u && c4 == 103u && c5 == 114u && c6 == 111u && c7 == 117u && c8 == 110u && c9 == 100u && c10 == 45u && c11 == 99u && c12 == 111u && c13 == 108u && c14 == 111u && c15 == 114u) {
      (*style).bg_color = css_color_to_rgba(source, val_s, val_e);
    }
  }

  if (key_len == 12u) {
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

    if (c0 == 98u && c1 == 111u && c2 == 114u && c3 == 100u && c4 == 101u && c5 == 114u && c6 == 45u && c7 == 114u && c8 == 97u && c9 == 100u && c10 == 105u && c11 == 117u && c12 == 115u) {
      (*style).border_radius = parse_css_px(source, val_s, val_e);
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
