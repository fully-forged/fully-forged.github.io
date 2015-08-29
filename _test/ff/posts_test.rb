require 'minitest/autorun'
require 'ostruct'
require_relative '../../_plugins/ff/posts'

class Post
  attr_reader :data

  def initialize(attrs)
    @data = OpenStruct.new(attrs)
  end
end

describe FF::Posts do
  include FF::Posts

  before do
    @posts = [
      Post.new(title: 'Latest post 1', date: Time.new(2015,8,8)),
      Post.new(title: 'Latest post 2', date: Time.new(2015,8,5)),
      Post.new(title: 'August post 1', date: Time.new(2015,8,2)),
      Post.new(title: 'July post 2',   date: Time.new(2015,7,3)),
      Post.new(title: 'July post 3',   date: Time.new(2015,7,1)),
      Post.new(title: 'June post 1',   date: Time.new(2015,6,3)),
      Post.new(title: 'June post 2',   date: Time.new(2015,6,2)),
      Post.new(title: 'Older post 1',  date: Time.new(2015,5,3)),
      Post.new(title: 'Older post 2',  date: Time.new(2015,5,2)),
      Post.new(title: 'Older post 3',  date: Time.new(2015,4,2))
    ]
  end

  it "groups by date" do
    grouped = group_by_date(@posts)

    grouped["Latest articles"].count.must_equal(2)
    grouped["August 2015"].count.must_equal(1)
    grouped["July 2015"].count.must_equal(2)
    grouped["June 2015"].count.must_equal(2)
    grouped["Older articles"].count.must_equal(3)
  end
end
