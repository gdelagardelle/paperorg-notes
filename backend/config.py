from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    paperorg_jwt_secret: str = "dev-secret-change-in-production"
    paperorg_dev_mode: bool = True

    openai_api_key: str = ""
    elevenlabs_api_key: str = ""
    luxasr_api_key: str = ""

    pro_minutes_per_month: int = 600
    free_vocabulary_limit: int = 20

    apple_bundle_id: str = "com.paperorg.notes"
    apple_pro_product_id: str = "com.paperorg.notes.pro.monthly"


settings = Settings()
