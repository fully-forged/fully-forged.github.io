module FF
  class Figure < Liquid::Block
    def render(context)
      "<figure class='block-image'>#{super}</figure>"
    end
  end
end
