module GlueGun
  module Shared
    def detect_root_dir
      base_path = Module.const_source_location(self.class.name)&.first || ""
      File.dirname(base_path)
    end
  end
end
