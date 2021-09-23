using FeelingtouchUI;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UAnimation;
using UnityEngine;
using UnityEngine.Events;
using UnityEngine.UI;

[SLua.CustomLuaClass]
public partial class ObjectCache
{
    public static int MaxCacheId = 1000000;

    public static int EncodeCacheId(int realCacheId, int index)
    {
        return index * MaxCacheId + realCacheId;
    }

    public static int DecodeCacheId(int cacheId, out int index)
    {
        index = Mathf.FloorToInt(cacheId * 1.0f / MaxCacheId);
        return cacheId - index * MaxCacheId;
    }

    public static void SetActive(int cacheId, bool isActive)
    {
        var obj = ObjectCache.GetGameObject(cacheId, true);
        obj?.SetActive(isActive);
    }

    public static void SetImage(int cacheId, string imagePath, string imagePathExt, string localizeExt = "", bool isAsyncLoad = false)
    {
        var image = ObjectCache.GetComponent<Image>(cacheId, true);
        GOUtils.SetImage(image, imagePath, imagePathExt, localizeExt, isAsyncLoad);
    }

    public static void SetImageProgress(int cacheId, float progress)
    {
        var image = ObjectCache.GetComponent<Image>(cacheId, true);
        if (image != null)
        {
            image.fillAmount = progress;
        }
    }

    public static void SetText(int cacheId, string content)
    {
        var text = ObjectCache.GetComponent<Text>(cacheId, true);
        if (text == null)
        {
            return;
        }
        text.text = content;
    }

    public static string GetText(int cacheId)
    {
        var text = ObjectCache.GetComponent<Text>(cacheId, true);
        if (text == null)
        {
            return string.Empty;
        }
        return text.text;
    }

    // contentFlag 0数字  1GameString
    public static void SetText(int cacheId, int content, int contentFlag = 0)
    {
        var text = ObjectCache.GetComponent<Text>(cacheId, true);
        if (text == null)
        {
            return;
        }
        var str = string.Empty;
        switch(contentFlag)
        {
            case 0:
                {
                    using (zstring.Block())
                    {
                        str = zstring.Format("{0}", content).Intern();
                    }
                }
                break;
            case 1:
                {
                    str = GameStrings.Get(content);
                }
                break;
        }
        text.text = str;
    }

    public static void SetInputFieldText(int cacheId, string content)
    {
        var inputField = ObjectCache.GetComponent<InputField>(cacheId, true);
        if (inputField == null)
        {
            return;
        }
        inputField.text = content;
    }

    public static string GetInputFieldText(int cacheId)
    {
        var inputField = ObjectCache.GetComponent<InputField>(cacheId, true);
        if (inputField == null)
        {
            return string.Empty;
        }
        return inputField.text;
    }

    public static void SetInputFieldContentType(int cacheId, int type)
    {
        var inputField = ObjectCache.GetComponent<InputField>(cacheId, true);
        if (inputField == null) return;
        inputField.contentType = (InputField.ContentType)type;
    }

    public static int RefreshPoolContainer(int cacheId, string prefabName, string prefabFolder, int count = 1, string objName = "0")
    {
        var container = ObjectCache.GetComponent<GameObjectPoolContainer>(cacheId, true);
        return container == null ? 0 : container.RefreshPoolContainer(prefabName, prefabFolder, count, objName);
    }

    public static void ReleasePoolContainer(int cacheId)
    {
        var container = ObjectCache.GetComponent<GameObjectPoolContainer>(cacheId, true);
        container?.Release();
    }

    public static void SelectActionSelector(int cacheId, string actionName)
    {
        var selector = ObjectCache.GetComponent<ActionSelector>(cacheId, true);
        selector?.Select(actionName);
    }

    public static void SetCanvasGroup(int cacheId, float alphaFlag, int isInteractable, int isBlockRaycast, int isIgnoreParentGroup)
    {
        var canvasGroup = ObjectCache.GetComponent<CanvasGroup>(cacheId, true);
        GOUtils.SetCanvasGroup(canvasGroup, alphaFlag, isInteractable, isBlockRaycast, isIgnoreParentGroup);
    }

    public static void SetMultiColorItem(int cacheId, string optionName, int optionIndex)
    {
        var colorItem = ObjectCache.GetComponent<MultiColorItem>(cacheId, true);
        GOUtils.SetMultiColorItem(colorItem, optionName, optionIndex);
    }

    public static void SetMultiColorGroup(int cacheId, string itemName, string optionName, int optionIndex)
    {
        var colorGroup = ObjectCache.GetComponent<MultiColorGroup>(cacheId, true);
        GOUtils.SetMultiColorGroup(colorGroup, itemName, optionName, optionIndex);
    }

    public static void PlayTween(int cacheId, string tweenName, bool isPlayInverse = false, float duration = 0)
    {
        var tweenPlayer = ObjectCache.GetComponent<TweenPlayer>(cacheId, true);
        GOUtils.PlayTween(tweenPlayer, tweenName, isPlayInverse, duration);
    }

    public static void StopTween(int cacheId, string tweenName)
    {
        var tweenPlayer = ObjectCache.GetComponent<TweenPlayer>(cacheId, true);
        GOUtils.StopTween(tweenPlayer, tweenName);
    }

    public static void SetTweenEvent(int cacheId, string tweenName, Action onComplete, Action onStart)
    {
        var tweenPlayer = ObjectCache.GetComponent<TweenPlayer>(cacheId, true);
        GOUtils.SetTweenEvent(tweenPlayer, tweenName, onComplete, onStart);
    }

    public static void ClickButton(int cacheId)
    {
        var button = ObjectCache.GetComponent<Button>(cacheId, true);
        button?.onClick.Invoke();
    }

    public static bool AddClickEvent(int cacheId, UnityAction clickEvent)
    {
        var button = ObjectCache.GetComponent<Button>(cacheId, true);
        button?.onClick.AddListener(clickEvent);
        return true;
    }

    public static void RemoveClickEvent(int cacheId, UnityAction clickEvent = null)
    {
        var button = ObjectCache.GetComponent<Button>(cacheId, true);
        if (clickEvent == null)
        {
            button?.onClick.RemoveAllListeners();
        }
        else
        {
            button?.onClick.RemoveListener(clickEvent);
        }
    }

    public static void HidePage(int cacheId, bool popStack = true)
    {
        var uiPage = ObjectCache.GetComponent<UIPage>(cacheId, true);
        uiPage?.HideUIpage(popStack);
    }

    public static void SetParent(int cacheId, int parentCacheId, bool worldPositionStays, float posX = -1, float posY = -1, float posZ = -1, string name = "")
    {
        var obj = ObjectCache.GetGameObject(cacheId, true);
        var objParent = ObjectCache.GetGameObject(parentCacheId, true);
        GOUtils.SetParent(obj, objParent, worldPositionStays, posX, posY, posZ, name);
    }

    public static void SetLocalPosition(int cacheId, float posX, float posY, float posZ)
    {
        GOUtils.SetLocalPosition(ObjectCache.GetGameObject(cacheId, true), posX, posY, posZ);
    }

    public static void SetPosition(int cacheId, float posX, float posY, float posZ)
    {
        GOUtils.SetPosition(ObjectCache.GetGameObject(cacheId, true), posX, posY, posZ);
    }

    public static void SetPosition(int dstCacheId, int srcCacheId)
    {
        GOUtils.SyncPosition(ObjectCache.GetGameObject(dstCacheId, true), ObjectCache.GetGameObject(srcCacheId, true));        
    }

    public static void SetLocalEulerAngles(int cacheId, float angleX, float angleY, float angleZ)
    {
        GOUtils.SetLocalEulerAngles(ObjectCache.GetGameObject(cacheId, true), angleX, angleY, angleZ);
    }

    public static void SetLocalScale(int cacheId, float scaleX, float scaleY, float scaleZ)
    {
        GOUtils.SetLocalScale(ObjectCache.GetGameObject(cacheId, true), scaleX, scaleY, scaleZ);
    }

    public static void SetColor(int cacheId, float r, float g, float b, float a)
    {
        var graphic = ObjectCache.GetComponent<Graphic>(cacheId, true);
        if (graphic == null)
        {
            return;
        }
        graphic.color = new Color(r, g, b, a);
    }

    public static bool ExecQueueTask(int cacheId, Func<float> taskAction1, Func<float> taskAction2, Func<float> taskAction3, Func<float> taskAction4, int bindID = 0)
    {
        var queueTask = ObjectCache.GetComponent<GameQueueTask>(cacheId, true);
        if (queueTask == null)
        {
            return false;
        }
        return queueTask.ExecTask(taskAction1, taskAction2, taskAction3, taskAction4, bindID);
    }

    public static void ClearQueueTask(int cacheId)
    {
        var queueTask = ObjectCache.GetComponent<GameQueueTask>(cacheId, true);
        queueTask?.Clear();
    }

    public static void SetQueueTaskState(int cacheId, int state)
    {
        var queueTask = ObjectCache.GetComponent<GameQueueTask>(cacheId, true);
        if (queueTask == null)
        {
            return;
        }
        queueTask.Clear();

        switch (state)
        {
            case 1:
                {
                    queueTask.Wait();
                }
                break;
            case 2:
                {
                    queueTask.Pulse();
                }
                break;
            case 3:
                {
                    queueTask.Cancel();
                }
                break;
            case 4:
                {
                    queueTask.CancelAll();
                }
                break;
            default:
                break;
        }
    }

    public static void SetSpineEvent(int cacheId, System.Action<string> onActionEnd, System.Action<string> onAniEvent)
    {
        GOUtils.SetSpineEvent(ObjectCache.GetComponent<SpineHelper>(cacheId, true), onActionEnd, onAniEvent);
    }

    public static void StopSpine(int cacheId)
    {
        var compSpine = ObjectCache.GetComponent<SpineHelper>(cacheId, true);
        compSpine?.Stop();
    }

    public static void PlaySpine(int cacheId, string assetName, bool isAsync, string aniName, int playMode, System.Action<bool> onLoadDone = null, bool checkSameSpine = false)
    {
        GOUtils.PlaySpine(ObjectCache.GetComponent<SpineHelper>(cacheId, true), assetName, isAsync, aniName, playMode, onLoadDone, checkSameSpine);
    }

    public static void SetSpineTimeScale(int cacheId, float timeScale)
    {
        var compSpine = ObjectCache.GetComponent<SpineHelper>(cacheId, true);
        compSpine?.SetTimeScale(timeScale);
    }

    public static void SetSpineScale(int cacheId, float fScale, bool isOrigin)
    {
        var compSpine = ObjectCache.GetComponent<SpineHelper>(cacheId, true);
        compSpine?.SetSpineScale(fScale, isOrigin);
    }

    public static void TimerRunTask(int cacheId, string taskName, float delayTime, float repeatTime, int repeatCount, UnityAction taskAction, UnityAction repeatAction, UnityAction completeAction)
    {
        var compTimer = ObjectCache.GetComponent<UTimer>(cacheId, true);
        compTimer?.RunTask(taskName, delayTime, repeatTime, repeatCount, taskAction, repeatAction, completeAction);
    }

    public static void TimerStartTask(int cacheId, string taskName)
    {
        var compTimer = ObjectCache.GetComponent<UTimer>(cacheId, true);
        compTimer?.RunTask(taskName);
    }

    public static void TimerStopTask(int cacheId, string taskName)
    {
        var compTimer = ObjectCache.GetComponent<UTimer>(cacheId, true);
        if (string.IsNullOrEmpty(taskName))
        {
            compTimer?.StopAllTask();
        }
        else
        {
            compTimer?.StopTask(taskName);
        }
    }

    public static void TimerBegin(int cacheId)
    {
        var compTimer = ObjectCache.GetComponent<UTimer>(cacheId, true);
        compTimer?.Begin();
    }

    public static void TimerSetTaskEvent(int cacheId, string taskName, System.Action taskEventCallBack, System.Action repeatEventCallBack, System.Action completeEventCallBack)
    {
        var compTimer = ObjectCache.GetComponent<UTimer>(cacheId, true);
        compTimer?.SetTaskEvent(taskName, taskEventCallBack, repeatEventCallBack, completeEventCallBack);
    }

    public static void SetSelectable(int cacheId, int isSelectable)
    {
        if (isSelectable != -1)
        {
            var compSelectable = ObjectCache.GetComponent<Selectable>(cacheId, true);
            if (compSelectable != null)
            {
                compSelectable.interactable = isSelectable != 0;
            }
        }
    }

    public static void SetEffectGroup(int cacheId, int isGray, int isGlow)
    {
        var compEffect = ObjectCache.GetComponent<UIEffectGroup>(cacheId, true);
        if (compEffect != null)
        {
            compEffect.enableGrey = isGray == -1 ? compEffect.enableGrey : (isGray != 0);
            compEffect.enableGlow = isGlow == -1 ? compEffect.enableGlow : (isGlow != 0);
        }
    }

    public static void TextValueTo(int cacheId, float beginNum, float endNum, float duration, string format, float deltaTime = 0, UnityAction endAction = null, bool isUpdateByDelta = false, GameLoop loop = null)
    {
        var compTextValueTo = ObjectCache.GetComponent<UITextValueTo>(cacheId, true);
        compTextValueTo?.ExecValueTo(beginNum, endNum, duration, format, deltaTime, endAction, isUpdateByDelta, loop);
    }

    public static void TextRun(int cacheId, string content, int runTimes, float moveSpeed, float preWaitTime, float endWaitTime, Action onRunComplete)
    {
        var compTextRun = ObjectCache.GetComponent<UIRunText>(cacheId, true);
        GOUtils.TextRun(compTextRun, content, runTimes, moveSpeed, preWaitTime, endWaitTime, onRunComplete);
    }
    
    public static void ScrollBarValueTo(int cacheId, float beginNum, float endNum, float duration, UnityAction endAction = null, bool isUpdateByDelta = false)
    {
        var compScrollBarValueTo = ObjectCache.GetComponent<UIScrollbarValueTo>(cacheId, true);
        compScrollBarValueTo?.ExecValueTo(beginNum, endNum, duration, endAction, isUpdateByDelta);
    }

    public static void ImageValueTo(int cacheId, float beginNum, float endNum, float duration, UnityAction endAction = null, bool isUpdateByDelta = false, GameLoop loop = null)
    {
        var compImageValueTo = ObjectCache.GetComponent<UIImageValueTo>(cacheId, true);
        compImageValueTo?.ExecValueTo(beginNum, endNum, duration, endAction, isUpdateByDelta, loop);
    }

    public static void MultiImageValueTo(int cacheId, float beginPercent, int beginValueIndex, float endPercent, int endValueIndex, float duration, System.Action endAction = null, bool isUpdateByDelta = false)
    {
        var compMultiImageValueTo = ObjectCache.GetComponent<UIMultiImageValueTo>(cacheId, true);
        compMultiImageValueTo?.ExecValueTo(beginPercent, beginValueIndex, endPercent, endValueIndex, duration, endAction, isUpdateByDelta);
    }

    public static void SetMultiImageSingleEndCallBack(int cacheId, System.Action<bool, int> callBack)
    {
        var compMultiImageValueTo = ObjectCache.GetComponent<UIMultiImageValueTo>(cacheId, true);
        compMultiImageValueTo?.SetSingleEndCallBack(callBack);
    }

    public static void ResetMultiImageValueTo(int cacheId)
    {
        var compMultiImageValueTo = ObjectCache.GetComponent<UIMultiImageValueTo>(cacheId, true);
        compMultiImageValueTo?.Reset();
    }

    public static Tween TweenMoveTo(int cacheId, int fromCacheId, int endCacheId, float duration, float delay = 0, string easeName = null, bool removeAllTweens = false, Action onComplete = null)
    {
        var obj = ObjectCache.GetGameObject(cacheId, true);
        var objFrom = ObjectCache.GetGameObject(fromCacheId, true);
        var objEnd = ObjectCache.GetGameObject(endCacheId, true);
        return GOUtils.TweenMoveTo(obj, objFrom, objEnd, duration, delay, easeName, removeAllTweens, onComplete);
    }

    public static void SetLayer(int cacheId, string layerName, bool includeChildren = true)
    {
        var obj = ObjectCache.GetGameObject(cacheId, true);
        GOUtils.SetLayer(obj, layerName, includeChildren);
    }

    public static void FireUIEvent(int cacheId, string name)
    {
        var uiEvent = ObjectCache.GetComponent<UIEvent>(cacheId, true);
        uiEvent?.FireUIEvent(name);
    }

    public static void SetScrollBarSize(int cacheId, float size)
    {
        var scrollbar = ObjectCache.GetComponent<Scrollbar>(cacheId, true);
        if (scrollbar == null) return;
        scrollbar.size = size;
    }
}
