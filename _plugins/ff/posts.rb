require 'date'

module FF
  module Posts
    LATEST_POSTS_COUNT = 2
    LATEST_LABEL = "Latest articles"
    OLDER_LABEL  = "Older articles"

    def latest(posts)
      posts.take(LATEST_POSTS_COUNT)
    end

    def group_by_date(posts)
      latest = posts.take(LATEST_POSTS_COUNT)
      older = posts.drop(LATEST_POSTS_COUNT)

      if (older.size > 0)
        first_archive_post_date = extract_date(older.first.data["date"])
        # we go back 15 days and then round to the beginning of the month
        threshold = find_threshold(first_archive_post_date, 15)

        older.reduce({LATEST_LABEL => latest}) do |memo, post|
          month_key = month_key_for(post.data["date"], threshold)
          memo[month_key] ||= []
          memo[month_key] << post
          memo
        end
      else
        {LATEST_LABEL => latest}
      end
    end

    private

    def find_threshold(date, interval)
      exact_threshold = date - interval
      Date.new(exact_threshold.year,
               exact_threshold.month,
               1)
    end

    def month_key_for(post_time, threshold)
      d = extract_date(post_time)
      d < threshold ? OLDER_LABEL : format_date_label(d)
    end

    def extract_date(time_or_string)
      if time_or_string.respond_to?(:to_date)
        time_or_string.to_date
      else
        Time.parse(time_or_string).to_date
      end
    end

    def format_date_label(date)
      date.strftime("%B %Y")
    end
  end
end
