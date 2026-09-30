package com.paperorg.notes.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import com.paperorg.notes.R
import com.paperorg.notes.quickrecord.QuickRecordStore

/** One-tap voice note entry on Android Auto / Android for Cars. */
class QuickRecordCarScreen(carContext: CarContext) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        val recordRow = Row.Builder()
            .setTitle(carContext.getString(R.string.car_quick_record_title))
            .setBrowsable(false)
            .setOnClickListener {
                QuickRecordStore.launchMainActivity(carContext)
                finish()
            }
            .build()

        return ListTemplate.Builder()
            .setTitle(carContext.getString(R.string.app_name))
            .setHeaderAction(Action.APP_ICON)
            .setSingleList(
                ItemList.Builder()
                    .addItem(recordRow)
                    .build(),
            )
            .build()
    }
}
