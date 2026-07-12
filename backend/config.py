from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    paperorg_jwt_secret: str = "dev-secret-change-in-production"
    paperorg_dev_mode: bool = True

    # Empty = local SQLite file. Production: postgresql://user:pass@host:5432/dbname
    database_url: str = ""

    openai_api_key: str = ""
    elevenlabs_api_key: str = ""
    luxasr_api_key: str = ""

    pro_minutes_per_month: int = 600
    free_vocabulary_limit: int = 20

    apple_bundle_id: str = "com.paperorg.notes"
    apple_pro_product_id: str = "com.paperorg.notes.pro.monthly"

    # App Store Server API (production subscription verification)
    apple_issuer_id: str = ""
    apple_key_id: str = ""
    apple_private_key: str = ""
    apple_use_sandbox: bool = True

    # Paperorg Platform (Phase C/D). Empty = platform integration off.
    # When set, Platform-issued RS256 JWTs are accepted (validated via JWKS)
    # and those users' minutes are metered on the Platform ledger.
    platform_api_url: str = ""  # e.g. https://poplatform.paperorg.com
    # Internal service token: lets notes-api pull provider API keys from the
    # Platform credentials vault (falls back to the env keys above).
    platform_internal_token: str = ""


settings = Settings()
