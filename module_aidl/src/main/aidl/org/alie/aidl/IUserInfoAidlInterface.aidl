// IUserInfoAidlInterface.aidl
package org.alie.aidl;
import org.alie.aidl.IUserInfo;
import org.alie.aidl.ICommonCallback;
// Declare any non-default types here with import statements

interface IUserInfoAidlInterface {
    int add(int a,int b);
    int getScore(in IUserInfo iUserInfo);
    int getNewScore(in List<IUserInfo> list);
    List<IUserInfo> getUserInfoList();
    void workToGetUserInfoList(ICommonCallback iCommonCallback);
    oneway void requestUsers(in IUserInfo iUserInfo, ICommonCallback iCommonCallback);
    oneway void requestUsersflow(in IUserInfo iUserInfo, ICommonCallback iCommonCallback);
    oneway void cancelRequestUsersflow(ICommonCallback iCommonCallback);
}