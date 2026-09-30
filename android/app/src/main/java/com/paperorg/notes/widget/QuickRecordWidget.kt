package com.paperorg.notes.widget

import android.content.Context
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.paperorg.notes.R
import com.paperorg.notes.quickrecord.QuickRecordStore

class QuickRecordWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceTheme {
                Box(
                    modifier = GlanceModifier
                        .fillMaxSize()
                        .background(ColorProvider(Color(0xFFF5F7FB)))
                        .clickable(actionRunCallback<MarkQuickRecordAction>()),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Image(
                            provider = ImageProvider(R.drawable.launch_logo),
                            contentDescription = null,
                            modifier = GlanceModifier.size(48.dp),
                        )
                        Text(
                            text = context.getString(R.string.widget_quick_record_label),
                            style = TextStyle(
                                color = ColorProvider(Color(0xFF142337)),
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                            modifier = GlanceModifier.padding(top = 8.dp),
                        )
                    }
                }
            }
        }
    }
}

class MarkQuickRecordAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        QuickRecordStore.launchMainActivity(context)
    }
}

class QuickRecordWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = QuickRecordWidget()
}
