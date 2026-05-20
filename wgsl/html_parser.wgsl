fn create_dom_node(
  dom_tree: ptr<storage, DomRootTree, read_write>,
  node_type_val: u32,
  parent_idx_val: u32
) -> u32 {
  let idx = (*dom_tree).total_node;
  if (idx >= MAX_DOM_NODES) { return idx; }

  var node: DomNode;
  node.node_type = node_type_val;
  node.tag_name_off = 0u;
  node.tag_name_len = 0u;
  node.parent_idx = parent_idx_val;
  node.first_child = MAX_DOM_NODES;
  node.next_sibling = MAX_DOM_NODES;
  node.attr_count = 0u;
  node.style = init_style();

  if (parent_idx_val < MAX_DOM_NODES) {
    var parent_node = &(*dom_tree).nodes[parent_idx_val];
    if ((*parent_node).first_child == MAX_DOM_NODES) {
      (*parent_node).first_child = idx;
    } else {
      var sibling_idx = (*parent_node).first_child;
      while ((*dom_tree).nodes[sibling_idx].next_sibling != MAX_DOM_NODES) {
        sibling_idx = (*dom_tree).nodes[sibling_idx].next_sibling;
      }
      (*dom_tree).nodes[sibling_idx].next_sibling = idx;
    }
  }

  (*dom_tree).nodes[idx] = node;
  (*dom_tree).total_node += 1u;
  return idx;
}

fn parse_html(
  html_source: ptr<storage, array<u32>, read_write>,
  html_len: u32,
  dom_tree: ptr<storage, DomRootTree, read_write>
) {
  (*dom_tree).total_node = 0u;
  (*dom_tree).root_node_id = create_dom_node(dom_tree, 0u, MAX_DOM_NODES);

  var ctx: ParseContext;
  ctx.html_ptr = 0u;
  ctx.html_len = html_len;
  ctx.stack_ptr = 1u;
  ctx.node_stack[0] = (*dom_tree).root_node_id;
  ctx.in_comment = false;
  ctx.in_tag = false;
  ctx.current_node_idx = MAX_DOM_NODES;

  var text_start: u32 = MAX_DOM_NODES;
  var tag_start: u32 = MAX_DOM_NODES;

  while (ctx.html_ptr < ctx.html_len) {
    let c = (*html_source)[ctx.html_ptr];

    if (ctx.in_comment) {
      if (ctx.html_ptr + 2u < ctx.html_len &&
          (*html_source)[ctx.html_ptr] == 45u &&
          (*html_source)[ctx.html_ptr + 1u] == 45u &&
          (*html_source)[ctx.html_ptr + 2u] == 62u) {
        ctx.in_comment = false;
        ctx.html_ptr += 3u;
        continue;
      }
      ctx.html_ptr += 1u;
      continue;
    }

    if (c == 60u) {
      if (text_start != MAX_DOM_NODES) {
        let is_blank = is_blank_text(html_source, text_start, ctx.html_ptr);
        if (!is_blank) {
          let text_idx = create_dom_node(dom_tree, 1u, ctx.node_stack[ctx.stack_ptr - 1u]);
          var text_node = &(*dom_tree).nodes[text_idx];
          (*text_node).tag_name_off = text_start;
          (*text_node).tag_name_len = ctx.html_ptr - text_start;
          (*text_node).style.is_text_node = true;
          let size = text_content_tokenize(html_source, text_start, ctx.html_ptr);
          (*text_node).style.content_w = size.x;
          (*text_node).style.content_h = size.y;
        }
        text_start = MAX_DOM_NODES;
      }

      if (ctx.html_ptr + 3u < ctx.html_len &&
          (*html_source)[ctx.html_ptr + 1u] == 33u &&
          (*html_source)[ctx.html_ptr + 2u] == 45u &&
          (*html_source)[ctx.html_ptr + 3u] == 45u) {
        ctx.in_comment = true;
        ctx.html_ptr += 4u;
        continue;
      }

      tag_start = ctx.html_ptr + 1u;
      ctx.in_tag = true;
      ctx.html_ptr += 1u;
      continue;
    }

    if (c == 62u && ctx.in_tag) {
      let is_close = (*html_source)[tag_start] == 47u;
      let tag_real_start = select(tag_start, tag_start + 1u, is_close);
      let tag_end = ctx.html_ptr;

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
        let new_idx = create_dom_node(dom_tree, node_type, ctx.node_stack[ctx.stack_ptr - 1u]);

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
          ctx.node_stack[ctx.stack_ptr] = new_idx;
          ctx.stack_ptr += 1u;
        }
      } else {
        if (ctx.stack_ptr > 1u) {
          ctx.stack_ptr -= 1u;
        }
      }

      ctx.in_tag = false;
      tag_start = MAX_DOM_NODES;
      ctx.html_ptr += 1u;
      continue;
    }

    if (!ctx.in_tag && text_start == MAX_DOM_NODES && !is_blank_char(c)) {
      text_start = ctx.html_ptr;
    }

    ctx.html_ptr += 1u;
  }
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

  while (ptr < end && attr_count < MAX_ATTRS) {
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
