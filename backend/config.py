from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Empty is permitted only for local SQLite development. Production startup
    # rejects weak or default signing secrets before serving any request.
    paperorg_jwt_secret: str = ""
    paperorg_dev_mode: bool = False

    # Empty = local SQLite file. Production: postgresql://user:pass@host:5432/dbname
    database_url: str = ""

    openai_api_key: str = ""
    elevenlabs_api_key: str = ""
    luxasr_api_key: str = ""

    pro_minutes_per_month: int = 600
    free_included_minutes_enabled: bool = False
    free_minutes_per_month: int = 30
    free_vocabulary_limit: int = 20
    transcription_requests_per_15_minutes: int = 12

    apple_bundle_id: str = "com.paperorg.notes"
    apple_pro_product_id: str = "com.paperorg.notes.pro.monthly"

    # App Store Server API (production subscription verification)
    apple_issuer_id: str = ""
    apple_key_id: str = ""
    apple_private_key: str = ""
    apple_use_sandbox: bool = True
    # Directory containing Apple root certificates downloaded from Apple PKI.
    # Required to verify App Store transaction and notification JWS chains.
    apple_root_certificates_dir: str = ""
    # Production-only numeric App Store Connect app ID for signed-data checks.
    apple_app_id: int = 6789115903

    # Paperorg Platform (Phase C/D). Empty = platform integration off.
    # When set, Platform-issued RS256 JWTs are accepted (validated via JWKS)
    # and those users' minutes are metered on the Platform ledger.
    platform_api_url: str = ""  # e.g. https://poplatform.paperorg.com
    # Internal service token: lets notes-api pull provider API keys from the
    # Platform credentials vault. When both are configured, that vault is
    # authoritative and local provider-key fallbacks are disabled.
    platform_internal_token: str = ""

    # Server-side email relay (used by the iOS app for hands-free auto-send).
    email_smtp_host: str = ""
    email_smtp_port: int = 465
    email_smtp_username: str = ""
    email_smtp_password: str = ""
    email_from_address: str = "notes@paperorg.com"
    email_from_name: str = "Paperorg Notes"
    email_daily_limit: int = 50


settings = Settings()
