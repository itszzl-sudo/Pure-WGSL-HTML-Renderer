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
  var color = vec4<f32>(1.0, 1.0, 1.0, 1.0);

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
            color = mix(color, (*node).style.text_color, 0.9);
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
