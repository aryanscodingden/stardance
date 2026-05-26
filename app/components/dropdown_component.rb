class DropdownComponent < ViewComponent::Base
  attr_reader :label, :options, :selected_option, :color, :longest_option_string, :action

  def initialize(label:, options:, selected_option:, longest_option_string: nil, color: :brown, action: nil)
    @label = label
    @options = options
    @selected_option = selected_option
    @longest_option_string = longest_option_string
    @color = color
    @action = action
  end

  def selected_value
    opt = options.find do |o|
      if o.is_a?(Hash)
        o[:label].to_s == selected_option.to_s || o[:value].to_s == selected_option.to_s
      else
        o.to_s == selected_option.to_s
      end
    end
    opt.is_a?(Hash) ? opt[:value] : opt
  end
end
