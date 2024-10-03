guard :rspec, cmd: "bundle exec rspec" do
  watch(%r{^spec/.+_spec\.rb$}) { |_m| "spec/glue_gun_spec.rb" }
  watch(%r{^lib/(.+)\.rb$}) { |_m| "spec/glue_gun_spec.rb" }
end
