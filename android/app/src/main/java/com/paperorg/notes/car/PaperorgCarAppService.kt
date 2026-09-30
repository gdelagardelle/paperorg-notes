package com.paperorg.notes.car

import android.content.Intent
import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

class PaperorgCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator =
        HostValidator.ALLOW_ALL_HOSTS_VALIDATOR

    override fun onCreateSession(): Session = PaperorgCarSession()
}

private class PaperorgCarSession : Session() {
    override fun onCreateScreen(intent: Intent) = QuickRecordCarScreen(carContext)
}
