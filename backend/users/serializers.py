from rest_framework import serializers
from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password

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
    # این فیلدها رو به صورت متد اضافه می‌کنیم تا از دیکشنری‌ای که ویو پاس می‌ده بخونن
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

    def get_watched_movies_count(self, obj):
        # این مقدار توسط ویو (ProfileView) داخل context یا __dict__ قرار می‌گیره
        return getattr(obj, '_watched_movies_count', 0)

    def get_watched_shows_count(self, obj):
        return getattr(obj, '_watched_shows_count', 0)

    def get_favorite_items(self, obj):
        return getattr(obj, '_favorite_items', [])