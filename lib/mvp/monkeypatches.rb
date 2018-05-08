# BigQuery uses newline delimited json
# https://en.wikipedia.org/wiki/JSON_streaming#Line-delimited_JSON

class Array
  def to_newline_delimited_json
    self.map(&:to_json).join("\n")
  end
end
