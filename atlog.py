
from passlib.context import CryptContext

@router.get("/sso_login")
async def sso_login(
    db: DbSession,
    email: str = Query(..., description="User email"),
    token: str = Query(..., description="SSO token (JWT or random for dev)"),
):
    if not token or not isinstance(token, str):
        raise HTTPException(status_code=401, detail="Missing or invalid SSO token.")

    # TODO: Validate the JWT here for production

    email = email.strip().lower()
    user = await get_user_by_username(db, email)

    # ---- SSO password logic: ----
    SSO_DEFAULT_PASSWORD = "sso_user_secret"  # IMPORTANT: Must match your frontend POST to /login!
    pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

    if not user:
        user = User(
            username=email,
            password=pwd_context.hash(SSO_DEFAULT_PASSWORD),  # <-- Use a hashed value, NOT empty string!
            is_superuser=False,
            is_active=True,
            last_login_at=None,
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)

    tokens = await create_user_tokens(user_id=user.id, db=db, update_last_login=True)
    auth_settings = get_settings_service().auth_settings

    redirect = RedirectResponse(url="/")
    redirect.set_cookie(
        "refresh_token_lf",
        tokens["refresh_token"],
        httponly=auth_settings.REFRESH_HTTPONLY,
        samesite=auth_settings.REFRESH_SAME_SITE,
        secure=auth_settings.REFRESH_SECURE,
        expires=auth_settings.REFRESH_TOKEN_EXPIRE_SECONDS,
        domain=auth_settings.COOKIE_DOMAIN,
    )
    redirect.set_cookie(
        "access_token_lf",
        tokens["access_token"],
        httponly=auth_settings.ACCESS_HTTPONLY,
        samesite=auth_settings.ACCESS_SAME_SITE,
        secure=auth_settings.ACCESS_SECURE,
        expires=auth_settings.ACCESS_TOKEN_EXPIRE_SECONDS,
        domain=auth_settings.COOKIE_DOMAIN,
    )
    redirect.set_cookie(
        "apikey_tkn_lflw",
        str(user.store_api_key or ""),
        httponly=auth_settings.ACCESS_HTTPONLY,
        samesite=auth_settings.ACCESS_SAME_SITE,
        secure=auth_settings.ACCESS_SECURE,
        expires=None,
        domain=auth_settings.COOKIE_DOMAIN,
    )

    await get_variable_service().initialize_user_variables(user.id, db)
    _ = await get_or_create_default_folder(db, user.id)

    return redirect
