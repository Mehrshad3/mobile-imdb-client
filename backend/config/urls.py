from django.contrib import admin
from django.urls import path, include  # Make sure 'include' is imported
from django.conf.urls.static import static

from . import settings

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', include('gateway.urls')),
    path('api/users/', include('users.urls')),
    path('api/watch/', include('watch.urls')),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)