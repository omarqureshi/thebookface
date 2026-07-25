# Headless-Chrome driver for @javascript scenarios (the real browser image
# upload). cucumber-rails switches to Capybara.javascript_driver for @javascript
# tags automatically. Registering the driver doesn't launch Chrome — only running
# a @javascript scenario does — so this is harmless where Chrome is absent.

require "capybara/cuprite"

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [1200, 900],
    headless: true,
    process_timeout: 30,
    timeout: 30,
    browser_path: ENV["CHROMIUM_PATH"].presence, # nil => ferrum autodetects
    browser_options: {
      "no-sandbox" => nil,          # required running as root in a container
      "disable-gpu" => nil,
      "disable-dev-shm-usage" => nil # containers have a small /dev/shm
    }
  )
end

Capybara.javascript_driver = :cuprite
