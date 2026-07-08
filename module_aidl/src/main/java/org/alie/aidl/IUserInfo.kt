package org.alie.aidl

import android.os.Parcel
import android.os.Parcelable

data class IUserInfo(
    val name: String,
    val age: Int,
    val introduction: String
) : Parcelable {
    constructor(parcel: Parcel) : this(
        parcel.readString() ?: "",
        parcel.readInt(),
        parcel.readString() ?: ""
    )

    override fun writeToParcel(parcel: Parcel, flags: Int) {
        parcel.writeString(name)
        parcel.writeInt(age)
        parcel.writeString(introduction)
    }

    override fun describeContents(): Int = 0

    companion object CREATOR : Parcelable.Creator<IUserInfo> {
        override fun createFromParcel(parcel: Parcel): IUserInfo = IUserInfo(parcel)
        override fun newArray(size: Int): Array<IUserInfo?> = arrayOfNulls(size)
    }
}
