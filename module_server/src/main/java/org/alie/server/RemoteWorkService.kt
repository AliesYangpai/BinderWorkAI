package org.alie.server

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.alie.aidl.ICommonCallback
import org.alie.aidl.IUserInfo
import org.alie.aidl.IUserInfoAidlInterface
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentMap

class RemoteWorkService : Service() {
    private var tag = RemoteWorkService::class.java.toString()
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val taskMap = ConcurrentHashMap<ICommonCallback?, Job>()
    override fun onCreate() {
        Log.i(tag, "binderwork server onCreate")
        super.onCreate()
    }

    override fun onBind(intent: Intent): IBinder {
        Log.i(tag, "binderwork server onBind")
        return object : IUserInfoAidlInterface.Stub() {
            override fun add(a: Int, b: Int): Int {

                Log.i(tag, "binderwork server add a:$a b:$b")
                return (a + b) * 10
            }

            override fun getUserInfoList(): List<IUserInfo?>? {
                val list = listOf(
                    IUserInfo("tom", 12, "this is a cat"),
                    IUserInfo("jerry", 12, "this is a mouse"),
                    IUserInfo("lucas", 12, "this is a dog")
                )
                Log.i(tag, "binderwork server getUserInfoList size:${list.size}")
                return list
            }

            override fun workToGetUserInfoList(iCommonCallback: ICommonCallback?) {

                val list = listOf(
                    IUserInfo("tommmm", 12, "this is a cat"),
                    IUserInfo("jerryyy", 12, "this is a mouse"),
                    IUserInfo("lucassss", 12, "this is a dog")
                )
                iCommonCallback?.onSuccess(list[0].name)
            }

            override fun requestUsers(
                iUserInfo: IUserInfo?,
                iCommonCallback: ICommonCallback?
            ) {
                val iUserInfo = IUserInfo("lucassss", 12, "this is a dog")
                iCommonCallback?.onSuccess(iUserInfo.name)
            }

            override fun requestUsersflow(
                iUserInfo: IUserInfo?,
                iCommonCallback: ICommonCallback?
            ) {
                taskMap[iCommonCallback]?.cancel()
                val job = serviceScope.launch {
                    val iUserInfo = IUserInfo("john work", 12, "this is a dog")
                    delay(300)
                    iCommonCallback?.onSuccess(iUserInfo.name)
                    taskMap.remove(iCommonCallback)
                }
                taskMap[iCommonCallback] = job
            }

            override fun cancelRequestUsersflow(iCommonCallback: ICommonCallback?) {
                    taskMap.remove(iCommonCallback)?.cancel()
            }

            override fun getScore(iUserInfo: IUserInfo?): Int {
                Log.i(tag, "binderwork server getScore iUserInfo:$iUserInfo")
                return 87
            }

            override fun getNewScore(list: List<IUserInfo?>?): Int {
                Log.i(tag, "binderwork server getNewScore listSize:${list?.size}")
                return 88
            }
        }
    }
}