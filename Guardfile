guard :rspec, cmd: "bundle exec rspec" do
  watch(%r{^spec/.+_spec\.rb$}) { |_m| "spec/model_spec.rb" }
  watch(%r{^lib/(.+)\.rb$}) { |_m| "spec/model_spec.rb" }
end
