package org.alie.client

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.launch
import org.alie.aidl.ICommonCallback
import org.alie.aidl.IUserInfo
import org.alie.aidl.IUserInfoAidlInterface
import org.alie.client.databinding.ActivityMainBinding

class MainActivity : AppCompatActivity() {
    private var tag = MainActivity::class.java.toString()

    private lateinit var mBinding: ActivityMainBinding

    private var proxy: IUserInfoAidlInterface? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
//        enableEdgeToEdge()
        mBinding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(mBinding.root)



        mBinding.btn1.setOnClickListener {
            bindService(Intent().apply {
                action = "org.alie.server.bindserver"
                setPackage("org.alie.server")
            }, object : ServiceConnection {
                override fun onServiceConnected(
                    name: ComponentName?,
                    iBinder: IBinder?
                ) {
                    proxy = IUserInfoAidlInterface.Stub.asInterface(iBinder)
                    Log.i(tag, "binderwork client onServiceConnected proxy : $proxy")
                }

                override fun onServiceDisconnected(p0: ComponentName?) {
                    Log.i(tag, "binderwork client onServiceDisconnected ")
                }
            }, Context.BIND_AUTO_CREATE)
        }

        mBinding.btn2.setOnClickListener {
            mBinding.tv1.text = proxy?.add(5, 9).toString()
        }

        mBinding.btn3.setOnClickListener {
            mBinding.tv1.text = proxy?.getScore(IUserInfo("tom", 12, "this is a cat")).toString()
        }
        mBinding.btn4.setOnClickListener {
            mBinding.tv1.text = proxy?.getNewScore(
                listOf(
                    IUserInfo("tom", 12, "this is a cat"),
                    IUserInfo("jerry", 12, "this is a mouse"),
                    IUserInfo("gether", 12, "this is a dag")
                )
            ).toString()
        }

        mBinding.btn5.setOnClickListener {
            mBinding.tv1.text = proxy?.userInfoList?.get(0)?.introduction
        }
        mBinding.btn6.setOnClickListener {
             proxy?.workToGetUserInfoList(object : ICommonCallback.Stub() {
                override fun onSuccess(dataMsg: String?) {
                        mBinding.tv1.text = dataMsg
                }


                 override fun onFail(msgMsg: String?) {
                     mBinding.tv1.text = msgMsg
                 }

             })
        }
        mBinding.btn7.setOnClickListener {
            proxy?.requestUsers(
                IUserInfo("tom", 12, "this is a cat"), object : ICommonCallback.Stub() {
                    override fun onSuccess(dataMsg: String?) {
                        Log.i(tag, "binderwork client requestUsers thread:${Thread.currentThread()} ")
                        mBinding.tv1.text = dataMsg
                    }

                    override fun onFail(msgMsg: String?) {
                    }
                })
        }
        mBinding.btn8.setOnClickListener {
//            CoroutineScope(Dispatchers.IO).launch {
//                workBtn8()
//            }
            lifecycleScope.launch {

                workBtn8()
            }


        }


    }
    private suspend fun workBtn8() {

            callbackFlow {
            val callback =  object : ICommonCallback.Stub() {
                override fun onSuccess(dataMsg: String?) {
                    val result =  trySendBlocking(dataMsg)
                    if (result.isClosed) {
                        close()
                    }
                }

                override fun onFail(msgMsg: String?) {
                    trySendBlocking(msgMsg)
                    close()
                }

            }
            proxy?.requestUsersflow(IUserInfo("tommmLijohns", 12, "this is a cat"),callback)
            awaitClose {
                proxy?.cancelRequestUsersflow(callback)
            }
        }.buffer(
            capacity = 10,
            onBufferOverflow = BufferOverflow.DROP_OLDEST
        ).flowOn(Dispatchers.IO)
            .collect {
                mBinding?.tv1?.text = it
                Log.i(tag, "binderwork client workBtn8  it : $it ${Thread.currentThread()}")
        }
    }
}