TILE_WIDTH = 256
MAX_ZOOM = 19
MAX_ZOOM_DIFF = 8

class MatrixManager
  attr_reader :top_row, :left_col, :offset_x, :offset_y, :zoom, :show_cov, :cov_zoom

  def initialize(width, height, config)
    @show_cov = config['show_cov']
    @cov_zoom = config['cov_zoom']
    @zoom = config['zoom']
    @left_col = config['left_col']
    @top_row = config['top_row']
    @offset_x = config['offset_x']
    @offset_y = config['offset_y']
    @width = width
    @height = height
    create_matrix
  end

  def config
    result = {}
    %w(left_col top_row offset_x offset_y zoom show_cov cov_zoom).each do |attr|
      result[attr] = self.send(attr)
    end
    result
  end

  def zoom_in(x, y)
    if @zoom < MAX_ZOOM
      @zoom += 1
      @cov_zoom = zoom + 1 if cov_zoom - zoom < 1
      @offset_x, @left_col = calc_start_and_offset_zoom_in(@left_col, x, @offset_x, @width)
      @offset_y, @top_row = calc_start_and_offset_zoom_in(@top_row, y, @offset_y, @height)
      create_matrix
    end
  end

  def zoom_out(x, y)
    if @zoom > 0
      @zoom -= 1
      @cov_zoom = zoom + MAX_ZOOM_DIFF if cov_zoom - zoom > MAX_ZOOM_DIFF
      @offset_x, @left_col = calc_start_and_offset_zoom_out(@left_col, x, @offset_x, @width)
      @offset_y, @top_row = calc_start_and_offset_zoom_out(@top_row, y, @offset_y, @height)
      create_matrix
    end
  end

  def draw(dc)
    @matrix.each do |col, row, tile|
      tile.draw(dc, TILE_WIDTH * (col - 1) + @offset_x, TILE_WIDTH * (row - 1) + @offset_y)
    end
  end

  def draw_tile(dc, the_tile)
    @matrix.each do |col, row, tile|
      if tile == the_tile
        tile.draw(dc, TILE_WIDTH * (col - 1) + @offset_x, TILE_WIDTH * (row - 1) + @offset_y)
        break
      end
    end
  end

  def toggle_coverage
    @show_cov = !show_cov
    recreate_coverage
  end

  def coverage_zoom_in
    if cov_zoom - zoom < MAX_ZOOM_DIFF
      @cov_zoom += 1
      recreate_coverage
    end
  end

  def coverage_zoom_out
    if cov_zoom - zoom > 1
      @cov_zoom -= 1
      recreate_coverage
    end
  end

  def pan(dx, dy)
    @offset_x += dx
    @offset_y += dy

    if @offset_x < 0
      @offset_x = TILE_WIDTH + @offset_x
      @left_col += 1
      @matrix.shift_left(get_tiles(:column, :last) )
    elsif @offset_x >= TILE_WIDTH
      @offset_x -= TILE_WIDTH
      @left_col -= 1
      @matrix.shift_right(get_tiles(:column, :first) )
    end

    if @offset_y < 0
      @offset_y = TILE_WIDTH + @offset_y
      @top_row += 1
      @matrix.shift_up(get_tiles(:row, :last) )
    elsif @offset_y >= TILE_WIDTH
      @offset_y -= TILE_WIDTH
      @top_row -= 1
      @matrix.shift_down(get_tiles(:row, :first) )
    end
  end

  def resize(viewport_width, viewport_height)
    @width = viewport_width
    @height = viewport_height
    new_matrix_width = (viewport_width.to_f / TILE_WIDTH).ceil + 2
    new_matrix_height = (viewport_height.to_f / TILE_WIDTH).ceil + 2
    if new_matrix_width < @matrix.width || new_matrix_height < @matrix.height
      @matrix.reduce(new_matrix_width, new_matrix_height)
    else
      if new_matrix_width > @matrix.width
        (@left_col + @matrix.width..@left_col + new_matrix_width - 1).each do |col|
          column = []
          (@top_row..@top_row + @matrix.height - 1).each do |row|
            column << get_tile(col, row, @zoom)
          end
          @matrix.add_column(column)
        end
      end
      if new_matrix_height > @matrix.height
        (@top_row + @matrix.height..@top_row + new_matrix_height - 1).each do |r|
          row = []
          (@left_col..@left_col + new_matrix_width - 1).each do |col|
            row << get_tile(col, r, @zoom)
          end
          @matrix.add_row(row)
        end
      end
    end
  end

  def cov_value
    show_cov && cov_zoom
  end

  private

  def calc_start_and_offset_zoom_in(start_idx, cursor_pos, offset, viewport_size)
    middle_tile_idx = start_idx * 2 + 2 + (cursor_pos - offset).to_i / (TILE_WIDTH / 2)
    from_edge = 2 * ( (cursor_pos - offset).to_i % (TILE_WIDTH / 2) )
    calc_offset_and_first_idx(middle_tile_idx, viewport_size, from_edge)
  end

  def calc_start_and_offset_zoom_out(start_idx, cursor_pos, offset, viewport_size)
    cursor_tile_idx = start_idx + (cursor_pos - offset).to_i / TILE_WIDTH + 1
    middle_tile_idx = cursor_tile_idx / 2
    from_edge = ( (cursor_pos - offset).to_i % TILE_WIDTH +
                  ((cursor_tile_idx % 2 == 0) ? 0 : TILE_WIDTH) ) / 2
    calc_offset_and_first_idx(middle_tile_idx, viewport_size, from_edge)
  end

  def calc_offset_and_first_idx(middle_idx, viewport_size, from_tile_edge)
    [ (viewport_size / 2 - from_tile_edge) % TILE_WIDTH,
      middle_idx - ( (viewport_size / 2 - from_tile_edge) / TILE_WIDTH ) - 1 ]
  end

  def create_matrix
    @matrix = TileMatrix.new
    @matrix[0,0] = get_tile(@left_col, @top_row, @zoom)
    resize(@width, @height)
  end

  def get_tiles(what, which)
    size = (what == :row ? @matrix.width - 1 : @matrix.height - 1)
    col = @left_col
    row = @top_row
    if which == :last
      what == :column ? col += @matrix.width - 1 : row += @matrix.height - 1
    end
    (0..size).map do |index|
      get_tile(col + (what == :row ? index : 0),
               row + (what == :column ? index : 0), @zoom)
    end
  end

  def get_tile(col, row, zoom)
    Tile.new(wraparound(col, zoom), wraparound(row, zoom), zoom, cov_value)
  end

  def wraparound(value, zoom)
    max = 2 ** zoom
    value = max - (value.abs % max) if value < 0
    value = value % max if value >= max
    value
  end

  def recreate_coverage
    @matrix.each do |col, row, tile|
      tile.create_coverage(show_cov && cov_zoom)
    end
  end

end
