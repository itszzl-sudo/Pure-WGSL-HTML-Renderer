fn calculate_layout(
  dom_tree: ptr<storage, DomRootTree, read_write>
) {
  var root = &(*dom_tree).nodes[(*dom_tree).root_node_id];
  (*root).style.layout_x = 10.0;
  (*root).style.layout_y = 10.0;
  (*root).style.content_w = CANVAS_W - 20.0;
  (*root).style.content_h = CANVAS_H - 20.0;

  var stack: array<u32, 64>;
  var stack_size: u32 = 0u;

  stack[0] = (*dom_tree).root_node_id;
  stack_size = 1u;

  while (stack_size > 0u) {
    stack_size = stack_size - 1u;
    var parent_idx = stack[stack_size];

    var parent = &(*dom_tree).nodes[parent_idx];

    var current_x = (*parent).style.layout_x + (*parent).style.padding_left;
    var current_y = (*parent).style.layout_y + (*parent).style.padding_top;

    var child_idx = (*parent).first_child;
    while (child_idx != MAX_DOM_NODES && child_idx < (*dom_tree).total_node) {
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

      if ((*child).first_child != MAX_DOM_NODES && stack_size < 64u) {
        stack[stack_size] = child_idx;
        stack_size = stack_size + 1u;
      }

      child_idx = (*child).next_sibling;
    }
  }
}
