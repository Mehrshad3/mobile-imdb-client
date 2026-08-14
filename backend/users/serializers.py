from rest_framework import serializers
from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password

from watch.models import UserTitle, UserFavorite
from watch.serializers import UserFavoriteSerializer

User = get_user_model()

class UserRegistrationSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, required=True, validators=[validate_password])

    class Meta:
        model = User
        fields = ('id', 'username', 'email', 'first_name', 'last_name', 'password', 'bio', 'profile_picture')

    def create(self, validated_data):
        user = User.objects.create_user(
            username=validated_data['username'],
            email=validated_data['email'],
            first_name=validated_data.get('first_name', ''),
            last_name=validated_data.get('last_name', ''),
            password=validated_data['password'],
            bio=validated_data.get('bio', ''),
            profile_picture=validated_data.get('profile_picture', None)
        )
        return user


class UserProfileSerializer(serializers.ModelSerializer):
    watched_movies_count = serializers.SerializerMethodField(read_only=True)
    watched_shows_count = serializers.SerializerMethodField(read_only=True)
    favorite_items = serializers.SerializerMethodField(read_only=True)

    class Meta:
        model = User
        fields = (
            'id', 'username', 'email', 'bio', 'profile_picture', 
            'watched_movies_count', 'watched_shows_count', 'favorite_items',
        )
        read_only_fields = ('id', 'email', 'username')

    # محاسبه‌ها مستقیماً روی دیتابیس و با شیء اصلی (obj) انجام می‌شوند
    def get_watched_movies_count(self, obj):
        return UserTitle.objects.filter(
            user=obj, title_type='movie', status='completed'
        ).count()

    def get_watched_shows_count(self, obj):
        return UserTitle.objects.filter(
            user=obj, title_type='tv', status='completed'
        ).count()

    def get_favorite_items(self, obj):
        favorites = UserFavorite.objects.filter(user=obj).order_by('-added_at')
        # ارسالِ context برای اطمینان از عملکردِ درستِ سریالایزرِ تو در تو
        return UserFavoriteSerializer(favorites, many=True, context=self.context).data