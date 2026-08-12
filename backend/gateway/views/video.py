import json
from django.http import JsonResponse
from django.views import View
from .base_scraper import BaseImdbScraper


class VideoScraper(BaseImdbScraper):
  def __init__(self, video_id):
    url = f"https://www.imdb.com/video/{video_id}/"
    super().__init__(url)

  def get_video_details(self):
    """استخراج لینک‌های مستقیم ویدیو از HTML صفحه"""
    if not self.soup:
      self.fetch_page()

    # پیدا کردن تگ JSON پنهان در HTML
    next_data_script = self.soup.find("script", id="__NEXT_DATA__")
    if not next_data_script:
      raise Exception("ویدیو پیدا نشد یا صفحه توسط IMDb تغییر کرده است.")

    data = json.loads(next_data_script.string)

    try:
      video_data = data["props"]["pageProps"]["videoPlaybackData"]["video"]

      # استخراج لینک‌های پخش مستقیم
      playback_urls = []
      for pb in video_data.get("playbackURLs", []):
        playback_urls.append({
            "quality": pb["displayName"]["value"],  # مثلاً 1080p, 720p, 480p
            "mime_type": pb["videoMimeType"],  # MP4 یا M3U8
            "url": pb["url"],  # لینک مستقیم و قابل استریم
        })

      return {
          "id": video_data.get("id"),
          "title": video_data.get("name", {}).get("value"),
          "thumbnail": video_data.get("thumbnail", {}).get("url"),
          "duration_seconds": video_data.get("runtime", {}).get("value"),
          "playback_urls": playback_urls,
      }
    except KeyError as e:
      raise Exception(f"خطا در استخراج ساختار ویدیو: {str(e)}")


class VideoStreamInfoView(View):
  def get(self, request, video_id):
    """API اصلی برای تحویل لینک‌های استریم به کلاینت فلاتر"""
    try:
      scraper = VideoScraper(video_id)
      video_info = scraper.get_video_details()
      return JsonResponse(
          {"status": "success", "data": video_info}, status=200
      )
    except Exception as e:
      return JsonResponse({"status": "error", "message": str(e)}, status=400)