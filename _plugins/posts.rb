require 'liquid'
require_relative 'ff/posts'
require_relative 'ff/figure'

Liquid::Template.register_filter(FF::Posts)
Liquid::Template.register_tag("figure", FF::Figure)
