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

public partial class ObjectCache
{
    public static void SetActive(int cacheId, int index, bool isActive)
    {
        var obj = ObjectCache.GetGameObject(cacheId, index);
        obj?.SetActive(isActive);
    }

    public static void SetEnable(int cacheId, int index, bool isEnable)
    {
        var component = ObjectCache.GetComponent(cacheId, index);
        if (component == null)
        {
            return;
        }
        var behaviour = component as Behaviour;
        if (behaviour == null)
        {
            return;
        }
        behaviour.enabled = isEnable;
    }

    public static void SetImage(int cacheId, int index, string imagePath, string imagePathExt, string localizeExt = "", bool isAsyncLoad = false)
    {
        var image = ObjectCache.GetComponent<Image>(cacheId, index);
        GOUtils.SetImage(image, imagePath, imagePathExt, localizeExt, isAsyncLoad);
    }

    public static void SetImageProgress(int cacheId, int index, float progress)
    {
        var image = ObjectCache.GetComponent<Image>(cacheId, index);
        if (image != null)
        {
            image.fillAmount = progress;
        }
    }

    public static void SetText(int cacheId, int index, string content)
    {
        var text = ObjectCache.GetComponent<Text>(cacheId, index);
        if (text == null)
        {
            return;
        }
        text.text = content;
    }

    public static string GetText(int cacheId, int index)
    {
        var text = ObjectCache.GetComponent<Text>(cacheId, index);
        if (text == null)
        {
            return string.Empty;
        }
        return text.text;
    }

    // contentFlag 0数字  1GameString
    public static void SetText(int cacheId, int index, int content, int contentFlag = 0)
    {
        var text = ObjectCache.GetComponent<Text>(cacheId, index);
        if (text == null)
        {
            return;
        }
        var str = string.Empty;
        switch (contentFlag)
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

    public static void SetInputFieldText(int cacheId, int index, string content)
    {
        var inputField = ObjectCache.GetComponent<InputField>(cacheId, index);
        if (inputField == null)
        {
            return;
        }
        inputField.text = content;
    }

    public static string GetInputFieldText(int cacheId, int index)
    {
        var inputField = ObjectCache.GetComponent<InputField>(cacheId, index);
        if (inputField == null)
        {
            return string.Empty;
        }
        return inputField.text;
    }

    public static void SetInputFieldContentType(int cacheId, int index, int type)
    {
        var inputField = ObjectCache.GetComponent<InputField>(cacheId, index);
        if (inputField == null) return;
        inputField.contentType = (InputField.ContentType)type;
    }

    public static int RefreshPoolContainer(int cacheId, int index, string prefabName, string prefabFolder, int count = 1, string objName = "0")
    {
        var container = ObjectCache.GetComponent<GameObjectPoolContainer>(cacheId, index);
        return container == null ? 0 : container.RefreshPoolContainer(prefabName, prefabFolder, count, objName);
    }

    public static void ReleasePoolContainer(int cacheId, int index)
    {
        var container = ObjectCache.GetComponent<GameObjectPoolContainer>(cacheId, index);
        container?.Release();
    }

    public static int GetPoolObjectInstanceID(int cacheId, int index, int objIndex = 0)
    {
        var container = ObjectCache.GetComponent<GameObjectPoolContainer>(cacheId, index);
        return container == null ? 0 : container.GetPoolObjectInstanceID(objIndex);
    }

    public static void SelectActionSelector(int cacheId, int index, string actionName)
    {
        var selector = ObjectCache.GetComponent<ActionSelector>(cacheId, index);
        selector?.Select(actionName);
    }

    public static void SetCanvasGroup(int cacheId, int index, float alphaFlag, int isInteractable, int isBlockRaycast, int isIgnoreParentGroup)
    {
        var canvasGroup = ObjectCache.GetComponent<CanvasGroup>(cacheId, index);
        GOUtils.SetCanvasGroup(canvasGroup, alphaFlag, isInteractable, isBlockRaycast, isIgnoreParentGroup);
    }

    public static void SetMultiColorItem(int cacheId, int index, string optionName, int optionIndex)
    {
        var colorItem = ObjectCache.GetComponent<MultiColorItem>(cacheId, index);
        GOUtils.SetMultiColorItem(colorItem, optionName, optionIndex);
    }

    public static void SetMultiColorGroup(int cacheId, int index, string itemName, string optionName, int optionIndex)
    {
        var colorGroup = ObjectCache.GetComponent<MultiColorGroup>(cacheId, index);
        GOUtils.SetMultiColorGroup(colorGroup, itemName, optionName, optionIndex);
    }

    public static void PlayTween(int cacheId, int index, string tweenName, bool isPlayInverse = false, float duration = 0)
    {
        var tweenPlayer = ObjectCache.GetComponent<TweenPlayer>(cacheId, index);
        GOUtils.PlayTween(tweenPlayer, tweenName, isPlayInverse, duration);
    }

    public static void StopTween(int cacheId, int index, string tweenName)
    {
        var tweenPlayer = ObjectCache.GetComponent<TweenPlayer>(cacheId, index);
        GOUtils.StopTween(tweenPlayer, tweenName);
    }

    public static void SetTweenEvent(int cacheId, int index, string tweenName, Action onComplete, Action onStart)
    {
        var tweenPlayer = ObjectCache.GetComponent<TweenPlayer>(cacheId, index);
        GOUtils.SetTweenEvent(tweenPlayer, tweenName, onComplete, onStart);
    }

    public static void ClickButton(int cacheId, int index)
    {
        var button = ObjectCache.GetComponent<Button>(cacheId, index);
        button?.onClick.Invoke();
    }

    public static bool AddClickEvent(int cacheId, int index, UnityAction clickEvent)
    {
        var button = ObjectCache.GetComponent<Button>(cacheId, index);
        button?.onClick.AddListener(clickEvent);
        return true;
    }

    public static void RemoveClickEvent(int cacheId, int index, UnityAction clickEvent = null)
    {
        var button = ObjectCache.GetComponent<Button>(cacheId, index);
        if (clickEvent == null)
        {
            button?.onClick.RemoveAllListeners();
        }
        else
        {
            button?.onClick.RemoveListener(clickEvent);
        }
    }

    public static void HidePage(int cacheId, int index, bool popStack = true)
    {
        var uiPage = ObjectCache.GetComponent<UIPage>(cacheId, index);
        uiPage?.HideUIpage(popStack);
    }

    public static void SetParent(int cacheId, int index, int parentCacheId, int parentIndex, bool worldPositionStays, float posX = -1, float posY = -1, float posZ = -1, string name = "")
    {
        var obj = ObjectCache.GetGameObject(cacheId, index);
        var objParent = ObjectCache.GetGameObject(parentCacheId, parentIndex);
        GOUtils.SetParent(obj, objParent, worldPositionStays, posX, posY, posZ, name);
    }

    public static void SetLocalPosition(int cacheId, int index, float posX, float posY, float posZ)
    {
        GOUtils.SetLocalPosition(ObjectCache.GetGameObject(cacheId, index), posX, posY, posZ);
    }

    public static void SetPosition(int cacheId, int index, float posX, float posY, float posZ)
    {
        GOUtils.SetPosition(ObjectCache.GetGameObject(cacheId, index), posX, posY, posZ);
    }

    public static void SyncPosition(int dstCacheId, int dstIndex, int srcCacheId, int srcIndex, int dstCameraId = 0, int srcCameraId = 0)
    {
        GOUtils.SyncPosition(ObjectCache.GetGameObject(dstCacheId, dstIndex), ObjectCache.GetGameObject(srcCacheId, srcIndex), ObjectCache.GetComponent<Camera>(dstCameraId), ObjectCache.GetComponent<Camera>(srcCameraId));
    }

    public static void SetLocalEulerAngles(int cacheId, int index, float angleX, float angleY, float angleZ)
    {
        GOUtils.SetLocalEulerAngles(ObjectCache.GetGameObject(cacheId, index), angleX, angleY, angleZ);
    }

    public static void SetLocalScale(int cacheId, int index, float scaleX, float scaleY, float scaleZ)
    {
        GOUtils.SetLocalScale(ObjectCache.GetGameObject(cacheId, index), scaleX, scaleY, scaleZ);
    }

    public static void SetColor(int cacheId, int index, float r, float g, float b, float a)
    {
        var graphic = ObjectCache.GetComponent<Graphic>(cacheId, index);
        if (graphic == null)
        {
            return;
        }
        graphic.color = new Color(r, g, b, a);
    }

    public static bool ExecQueueTask(int cacheId, int index, Func<float> taskAction1, Func<float> taskAction2, Func<float> taskAction3, Func<float> taskAction4, int bindID = 0)
    {
        var queueTask = ObjectCache.GetComponent<GameQueueTask>(cacheId, index);
        if (queueTask == null)
        {
            return false;
        }
        return queueTask.ExecTask(taskAction1, taskAction2, taskAction3, taskAction4, bindID);
    }

    public static void ClearQueueTask(int cacheId, int index)
    {
        var queueTask = ObjectCache.GetComponent<GameQueueTask>(cacheId, index);
        queueTask?.Clear();
    }

    public static void SetQueueTaskState(int cacheId, int index, int state)
    {
        var queueTask = ObjectCache.GetComponent<GameQueueTask>(cacheId, index);
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

    public static void SetSpineEvent(int cacheId, int index, System.Action<string> onActionEnd, System.Action<string> onAniEvent)
    {
        GOUtils.SetSpineEvent(ObjectCache.GetComponent<SpineHelper>(cacheId, index), onActionEnd, onAniEvent);
    }

    public static void StopSpine(int cacheId, int index)
    {
        var compSpine = ObjectCache.GetComponent<SpineHelper>(cacheId, index);
        compSpine?.Stop();
    }

    public static void PlaySpine(int cacheId, int index, string assetName, bool isAsync, string aniName, int playMode, System.Action<bool> onLoadDone = null, bool checkSameSpine = false)
    {
        GOUtils.PlaySpine(ObjectCache.GetComponent<SpineHelper>(cacheId, index), assetName, isAsync, aniName, playMode, onLoadDone, checkSameSpine);
    }

    public static void SetSpineTimeScale(int cacheId, int index, float timeScale)
    {
        var compSpine = ObjectCache.GetComponent<SpineHelper>(cacheId, index);
        compSpine?.SetTimeScale(timeScale);
    }

    public static void SetSpineScale(int cacheId, int index, float fScale, bool isOrigin)
    {
        var compSpine = ObjectCache.GetComponent<SpineHelper>(cacheId, index);
        compSpine?.SetSpineScale(fScale, isOrigin);
    }

    public static void TimerRunTask(int cacheId, int index, string taskName, float delayTime, float repeatTime, int repeatCount, UnityAction taskAction, UnityAction repeatAction, UnityAction completeAction)
    {
        var compTimer = ObjectCache.GetComponent<UTimer>(cacheId, index);
        compTimer?.RunTask(taskName, delayTime, repeatTime, repeatCount, taskAction, repeatAction, completeAction);
    }

    public static void TimerStartTask(int cacheId, int index, string taskName)
    {
        var compTimer = ObjectCache.GetComponent<UTimer>(cacheId, index);
        compTimer?.RunTask(taskName);
    }

    public static void TimerStopTask(int cacheId, int index, string taskName)
    {
        var compTimer = ObjectCache.GetComponent<UTimer>(cacheId, index);
        if (string.IsNullOrEmpty(taskName))
        {
            compTimer?.StopAllTask();
        }
        else
        {
            compTimer?.StopTask(taskName);
        }
    }

    public static void TimerBegin(int cacheId, int index)
    {
        var compTimer = ObjectCache.GetComponent<UTimer>(cacheId, index);
        compTimer?.Begin();
    }

    public static void TimerSetTaskEvent(int cacheId, int index, string taskName, System.Action taskEventCallBack, System.Action repeatEventCallBack, System.Action completeEventCallBack)
    {
        var compTimer = ObjectCache.GetComponent<UTimer>(cacheId, index);
        compTimer?.SetTaskEvent(taskName, taskEventCallBack, repeatEventCallBack, completeEventCallBack);
    }

    public static void SetSelectable(int cacheId, int index, int isSelectable)
    {
        if (isSelectable != -1)
        {
            var compSelectable = ObjectCache.GetComponent<Selectable>(cacheId, index);
            if (compSelectable != null)
            {
                compSelectable.interactable = isSelectable != 0;
            }
        }
    }

    public static void SetEffectGroup(int cacheId, int index, int isGray, int isGlow)
    {
        var compEffect = ObjectCache.GetComponent<UIEffectGroup>(cacheId, index);
        if (compEffect != null)
        {
            compEffect.enableGrey = isGray == -1 ? compEffect.enableGrey : (isGray != 0);
            compEffect.enableGlow = isGlow == -1 ? compEffect.enableGlow : (isGlow != 0);
        }
    }

    public static void TextValueTo(int cacheId, int index, float beginNum, float endNum, float duration, string format, float deltaTime = 0, UnityAction endAction = null, bool isUpdateByDelta = false, GameLoop loop = null)
    {
        var compTextValueTo = ObjectCache.GetComponent<UITextValueTo>(cacheId, index);
        compTextValueTo?.ExecValueTo(beginNum, endNum, duration, format, deltaTime, endAction, isUpdateByDelta, loop);
    }

    public static void TextRun(int cacheId, int index, string content, int runTimes, float moveSpeed, float preWaitTime, float endWaitTime, Action onRunComplete)
    {
        var compTextRun = ObjectCache.GetComponent<UIRunText>(cacheId, index);
        GOUtils.TextRun(compTextRun, content, runTimes, moveSpeed, preWaitTime, endWaitTime, onRunComplete);
    }

    public static void ScrollBarValueTo(int cacheId, int index, float beginNum, float endNum, float duration, UnityAction endAction = null, bool isUpdateByDelta = false)
    {
        var compScrollBarValueTo = ObjectCache.GetComponent<UIScrollbarValueTo>(cacheId, index);
        compScrollBarValueTo?.ExecValueTo(beginNum, endNum, duration, endAction, isUpdateByDelta);
    }

    public static void ImageValueTo(int cacheId, int index, float beginNum, float endNum, float duration, UnityAction endAction = null, bool isUpdateByDelta = false, GameLoop loop = null)
    {
        var compImageValueTo = ObjectCache.GetComponent<UIImageValueTo>(cacheId, index);
        compImageValueTo?.ExecValueTo(beginNum, endNum, duration, endAction, isUpdateByDelta, loop);
    }

    public static void MultiImageValueTo(int cacheId, int index, float beginPercent, int beginValueIndex, float endPercent, int endValueIndex, float duration, System.Action endAction = null, bool isUpdateByDelta = false)
    {
        var compMultiImageValueTo = ObjectCache.GetComponent<UIMultiImageValueTo>(cacheId, index);
        compMultiImageValueTo?.ExecValueTo(beginPercent, beginValueIndex, endPercent, endValueIndex, duration, endAction, isUpdateByDelta);
    }

    public static void SetMultiImageSingleEndCallBack(int cacheId, int index, System.Action<bool, int> callBack)
    {
        var compMultiImageValueTo = ObjectCache.GetComponent<UIMultiImageValueTo>(cacheId, index);
        compMultiImageValueTo?.SetSingleEndCallBack(callBack);
    }

    public static void ResetMultiImageValueTo(int cacheId, int index)
    {
        var compMultiImageValueTo = ObjectCache.GetComponent<UIMultiImageValueTo>(cacheId, index);
        compMultiImageValueTo?.Reset();
    }

    public static Tween TweenMoveTo(int cacheId, int index, int fromCacheId, int fromIndex, int endCacheId, int endIndex, float duration, float delay = 0, string easeName = null, bool removeAllTweens = false, Action onComplete = null)
    {
        var obj = ObjectCache.GetGameObject(cacheId, index);
        var objFrom = ObjectCache.GetGameObject(fromCacheId, fromIndex);
        var objEnd = ObjectCache.GetGameObject(endCacheId, endIndex);
        return GOUtils.TweenMoveTo(obj, objFrom, objEnd, duration, delay, easeName, removeAllTweens, onComplete);
    }

    public static void SetLayer(int cacheId, int index, string layerName, bool includeChildren = true)
    {
        var obj = ObjectCache.GetGameObject(cacheId, index);
        GOUtils.SetLayer(obj, layerName, includeChildren);
    }

    public static void FireUIEvent(int cacheId, int index, string name)
    {
        var uiEvent = ObjectCache.GetComponent<UIEvent>(cacheId, index);
        uiEvent?.FireUIEvent(name);
    }

    public static void SetScrollBarSize(int cacheId, int index, float size)
    {
        var scrollbar = ObjectCache.GetComponent<Scrollbar>(cacheId, index);
        if (scrollbar == null)
        {
            return;
        }
        scrollbar.size = size;
    }

    public static void SwitchSprite(int cacheId, int index, int option)
    {
        var switcher = ObjectCache.GetComponent<UISpriteSwitcher>(cacheId, index);
        switcher?.Switch(option);
    }

    public static void SetSizeFitterText(int cacheId, int index, string text)
    {
        var fitter = ObjectCache.GetComponent<UITextSizeFitter>(cacheId, index);
        if (fitter == null)
        {
            return;
        }
        fitter.text = text;
    }

    public static void LayoutUIContentSize(int cacheId, int index)
    {
        var fitter = ObjectCache.GetComponent<UIContentSizeFitter>(cacheId, index);
        fitter?.SetLayout();
    }

    // Add at v1.0.1.8
    public static void LayoutChildren(int cacheId, int index, int activeCount)
    {
        var obj = ObjectCache.GetGameObject(cacheId, index);
        GOUtils.LayoutChildren(obj, activeCount);
    }

    public static void FollowTarget(int cacheId, int index, int targetCacheId, int targetIndex)
    {
        var follower = ObjectCache.GetComponent<UIFollower>(cacheId, index);
        if (follower == null)
        {
            return;
        }
        follower.target = ObjectCache.GetComponent<Transform>(targetCacheId, targetIndex);
    }

    public static void SelectSliderItem(int cacheId, int index, int itemIndex, bool isRun = false)
    {
        var sliderList = ObjectCache.GetComponent<UISlideList>(cacheId, index);
        if (sliderList == null)
        {
            return;
        }
        if (isRun)
        {
            sliderList.RunToItem(itemIndex);
        }
        else
        {
            sliderList.SelectItem(itemIndex);
        }
    }
}