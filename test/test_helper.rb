gem "minitest"
require "minitest/autorun"

require "gosu" unless defined? Gosu

class Gosu::Image
  # Gosu does not implement this method by default because it is very inefficient.
  # However, it is useful for testing, and makes it easy to use assert_equal on images.
  def ==(other)
    if other.is_a? Gosu::Image
      (to_blob rescue object_id) == (other.to_blob rescue other.object_id)
    else
      false
    end
  end

  # Checks if two images are similar on a really basic level (check the difference of each channel)
  def similar?(img, threshold)
    return true if self == img
    return false unless img.is_a?(Gosu::Image)
    return false if self.width != img.width or self.height != img.height

    blob = img.to_blob
    differences = []

    self.to_blob.each_byte.with_index do |byte, idx|
      delta = (byte - blob.getbyte(idx)).abs
      differences << (delta / 255.0) if delta > 0
    end

    # If the average color difference is only subtle even on "large" parts of the image its still ok (e.g. differently rendered color gradients) OR
    # if the color difference is huge but on only a few pixels its ok too (e.g. a diagonal line may be off a few pixels)
    (1 - (differences.inject(:+) / differences.size) >= threshold) or (1 - (differences.size / blob.size.to_f) >= threshold)
  end
end

module TestHelper
  # TODO: Should be __dir__ after we drop Ruby 1.x support...
  def self.media_path(fname = "")
    File.join(File.dirname(__FILE__), "media", fname)
  end
  
  def media_path(fname = "")
    TestHelper.media_path(fname)
  end
  
  def skip_on_appveyor
    skip if ENV["APPVEYOR"]
  end

  def skip_on_travis
    skip if ENV["TRAVIS"]
  end

  def skip_on_ci
    skip if ENV["APPVEYOR"] or ENV["TRAVIS"]
  end
  
  def actual_from_expected_filename(expected)
    actual_basename = File.basename(expected, ".png") + ".actual.png"
    File.join(File.dirname(expected), actual_basename)
  end

  def assert_output_matches(expected, threshold, size)
    expected = File.expand_path("#{expected}.png", File.dirname(__FILE__))
    
    begin
      actual_image = Gosu.render(*size) { yield }
    rescue Exception => e
      if e.message.include? "GL_EXT_framebuffer_object"
        skip
        return
      end
    end

    actual_image.save actual_from_expected_filename(expected) if ENV["DEBUG"]

    expected_image = Gosu::Image.new(expected)

    message_proc = proc do
      message = "Screenshot should look similar to #{expected}"
      if ENV["TRAVIS"] || ENV["APPVEYOR"]
        # Print a diff when running in the CI so we can copy and paste the image if necessary.
        message += "\n"
        message += diff([expected_image.to_blob].pack('m*'), [actual_image.to_blob].pack('m*'))
      end
      message
    end
    assert actual_image.similar?(expected_image, threshold), message_proc
  end
end

module InteractiveTests
  def interactive_cli(message)
    return false unless ENV["GOSU_TEST_INTERACTIVE"]
    
    STDOUT.puts message + "Type (Y)es or (N)o or (S)kip and ENTER"
    yield if block_given?
    
    user_input = STDIN.gets
    if user_input =~ /[sS]/
      skip
    else
      assert user_input =~ /[yY]/, "User answered 'No' to '#{message}'"
    end
  end
  
  def interactive_gui(message)
    return false unless ENV["GOSU_TEST_INTERACTIVE"]
    
    STDOUT.puts message + "Press (Y)es or (N)o on your keyboard"
    win = yield
    win.extend InteractiveWindow
    
    assert_output "User answered 'Yes'\n", // do
      win.show
    end
  end
end

module InteractiveWindow
  def button_down(id)
    case Gosu.button_id_to_char(id)
    when "y"
      puts "User answered 'Yes'" 
      close!
    when "n"
      puts "User answered 'No'"
    end
  end
  
  def close
    puts "User canceled the test #{self.class}"
    close!
  end  
end
